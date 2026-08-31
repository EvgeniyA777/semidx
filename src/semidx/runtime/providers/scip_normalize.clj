(ns semidx.runtime.providers.scip-normalize
  "Stage 3 of the Semantic Provider Authority Migration (plans/018, ADR-046):
  normalize SCIP index data into provider-neutral facts for
  `semidx.runtime.fact-arbitration`.

  Input is the plain data returned by `semidx.runtime.scip/read-index`; output is
  a collection of `{:key <CanonicalFactKey> :evidence [<FactEvidence>]}` facts
  plus a record of every SCIP symbol that was deliberately not turned into a
  fact.

  Two pieces do the work:

  - `parse-scip-symbol` decomposes a SCIP symbol string into its scheme, package
    fields, and typed descriptors (namespace `/`, type `#`, term `.`, method
    `().`, parameter `(x)`, ...), handling backtick-escaped names.
  - `scip-symbol->unit` bridges a parsed TypeScript symbol onto semidx's own
    conceptual spelling — `ts-module-name` for the owner, `<module>/<name>` for a
    top-level function, `<module>.<Class>#<method>` for a method — so a SCIP
    moniker lands on the same `CanonicalFactKey` the regex and tree-sitter tiers
    already produce.

  Scope of this slice (owner-confirmed): only the definition kinds semidx models
  as units — top-level functions/vars and class methods. Classes, fields,
  constructors, parameters, and external/stdlib symbols are recorded as
  `:unmapped` with a reason and become no fact; whether SCIP should promote them
  as exact-only units is a later decision.

  Not in this slice: source-identity anchoring and artifact-freshness checks
  (the caller injects `source-identity`; the provider adapter computes the real
  digest and the stale-artifact gate), call-hierarchy facts (no `call/*`
  relation type exists), and any wiring into the default extraction path."
  (:require [clojure.string :as str]
            [semidx.runtime.language-registry :as language-registry]
            [semidx.runtime.languages.typescript :as ts]))

(def default-provider-id "scip-typescript")
(def default-provider-version "1")

;; --- SCIP symbol grammar ---------------------------------------------------
;;
;; <symbol>   ::= <scheme> ' ' <manager> ' ' <package-name> ' ' <version> ' ' <descriptor>+
;;              | 'local ' <local-id>
;; <name>     ::= <identifier> | '`' <escaped> '`'      ('``' is an escaped backtick)
;; descriptor suffixes: '/' namespace, '#' type, '.' term, '().' method,
;;                      '(x)' parameter, '[x]' type-parameter, ':' meta, '!' macro

(defn- read-name
  "Read a descriptor name from the front of `chars`. Returns [name remaining]."
  [chars]
  (if (= \` (first chars))
    (loop [cs (rest chars) acc []]
      (cond
        (empty? cs)
        (throw (ex-info "unterminated backtick-escaped SCIP name"
                        {:error_code :scip_symbol_parse_error}))
        (= \` (first cs))
        (if (= \` (second cs))
          (recur (drop 2 cs) (conj acc \`))
          [(apply str acc) (rest cs)])
        :else (recur (rest cs) (conj acc (first cs)))))
    (let [[name-chars remaining]
          (split-with (fn [^Character c]
                        (or (Character/isLetterOrDigit c) (#{\_ \$ \+ \-} c)))
                      chars)]
      [(apply str name-chars) remaining])))

(defn- read-descriptor
  "Read one descriptor from the front of `chars`. Returns [descriptor remaining]."
  [chars]
  (case (first chars)
    \( (let [[name remaining] (read-name (rest chars))]
         (when-not (= \) (first remaining))
           (throw (ex-info "malformed SCIP parameter descriptor"
                           {:error_code :scip_symbol_parse_error})))
         [{:kind :parameter :name name} (rest remaining)])
    \[ (let [[name remaining] (read-name (rest chars))]
         (when-not (= \] (first remaining))
           (throw (ex-info "malformed SCIP type-parameter descriptor"
                           {:error_code :scip_symbol_parse_error})))
         [{:kind :type-parameter :name name} (rest remaining)])
    (let [[name remaining] (read-name chars)]
      (case (first remaining)
        \/ [{:kind :namespace :name name} (rest remaining)]
        \# [{:kind :type :name name} (rest remaining)]
        \: [{:kind :meta :name name} (rest remaining)]
        \! [{:kind :macro :name name} (rest remaining)]
        \( (let [[disamb after] (split-with #(not= \) %) (rest remaining))]
             (when-not (and (= \) (first after)) (= \. (second after)))
               (throw (ex-info "malformed SCIP method descriptor"
                               {:error_code :scip_symbol_parse_error})))
             [{:kind :method :name name :disambiguator (apply str disamb)}
              (drop 2 after)])
        \. [{:kind :term :name name} (rest remaining)]
        (throw (ex-info "unexpected SCIP descriptor suffix"
                        {:error_code :scip_symbol_parse_error
                         :at (apply str (take 12 remaining))}))))))

(defn parse-scip-symbol
  "Parse a SCIP symbol string. Returns
  `{:scheme :manager :package-name :version :descriptors [...]}` for a global
  symbol, `{:scheme \"local\" :local-id ...}` for a local one, or `{:error ...}`
  when the string is empty or does not have the five space-separated fields."
  [sym]
  (cond
    (str/blank? sym)
    {:error :empty-symbol}

    (str/starts-with? sym "local ")
    {:scheme "local" :local-id (subs sym 6) :descriptors []}

    :else
    (let [parts (str/split sym #" " 5)]
      (if (< (count parts) 5)
        {:error :malformed-symbol :raw sym}
        (let [[scheme manager package-name version descriptor-str] parts]
          {:scheme scheme
           :manager manager
           :package-name package-name
           :version version
           :descriptors (loop [chars (seq descriptor-str) acc []]
                          (if (empty? chars)
                            acc
                            (let [[descriptor remaining] (read-descriptor chars)]
                              (recur remaining (conj acc descriptor)))))})))))

;; --- SCIP symbol -> semidx conceptual spelling ---------------------------

(defn- source-file-namespace?
  "A namespace descriptor whose name looks like an ecmascript source file."
  [descriptor]
  (and (= :namespace (:kind descriptor))
       (some #(str/ends-with? (:name descriptor) %)
             language-registry/ecmascript-source-extensions)))

(defn- split-path-and-symbol
  "Split leading namespace descriptors that reconstruct the source file path from
  the descriptors that name the symbol. The file is the first namespace whose
  name has a source extension. Returns {:path <\"src/orders.ts\"> :descriptors [...]}
  or {:path nil} when no file namespace is present."
  [descriptors]
  (loop [remaining descriptors
         path-parts []]
    (cond
      (empty? remaining)
      {:path nil}

      (source-file-namespace? (first remaining))
      {:path (str/join "/" (map :name (conj path-parts (first remaining))))
       :descriptors (vec (rest remaining))}

      (= :namespace (:kind (first remaining)))
      (recur (rest remaining) (conj path-parts (first remaining)))

      :else
      {:path nil})))

(defn- descriptors->owner+symbol
  "Map the symbol-naming descriptors (everything after the file namespace) onto
  semidx's TypeScript spelling, given the file's `module` name. Returns a unit
  map or `{:unmapped <reason>}`."
  [descriptors module]
  (let [kinds (map :kind descriptors)]
    (cond
      (empty? descriptors)
      {:unmapped :module-symbol}

      (some #{:parameter :type-parameter :meta :macro} kinds)
      {:unmapped :non-unit-descriptor}

      (and (= 1 (count descriptors))
           (#{:method :term} (:kind (first descriptors))))
      {:owner module
       :symbol (str module "/" (:name (first descriptors)))
       :kind "function"}

      (and (= 1 (count descriptors))
           (= :type (:kind (first descriptors))))
      {:unmapped :type-symbol}

      (and (= 2 (count descriptors))
           (= :type (:kind (first descriptors)))
           (= :method (:kind (second descriptors))))
      (if (= "<constructor>" (:name (second descriptors)))
        {:unmapped :constructor-symbol}
        (let [class-name (:name (first descriptors))]
          {:owner (str module "." class-name)
           :symbol (str module "." class-name "#" (:name (second descriptors)))
           :kind "function"}))

      (and (= 2 (count descriptors))
           (= :type (:kind (first descriptors)))
           (= :term (:kind (second descriptors))))
      {:unmapped :field-symbol}

      :else
      {:unmapped :unsupported-descriptor-shape})))

(defn scip-symbol->unit
  "Bridge a parsed SCIP TypeScript symbol onto a semidx unit identity. Returns
  `{:owner :symbol :kind :path}` for a mappable unit, otherwise
  `{:unmapped <reason>}`.

  `:external-symbol` covers anything defined in another package (package name is
  not the local-project `.`), e.g. a stdlib reference."
  [parsed]
  (cond
    (:error parsed)
    {:unmapped (:error parsed)}

    (= "local" (:scheme parsed))
    {:unmapped :local-symbol}

    (not= "." (:package-name parsed))
    {:unmapped :external-symbol}

    :else
    (let [{:keys [path descriptors]} (split-path-and-symbol (:descriptors parsed))]
      (if-not path
        {:unmapped :no-source-file-namespace}
        (let [module (ts/ts-module-name path)
              mapped (descriptors->owner+symbol descriptors module)]
          (if (:unmapped mapped)
            mapped
            (assoc mapped :path path)))))))

;; --- Fact emission -------------------------------------------------------

(defn- occurrence->fact
  "One occurrence of a mapped symbol becomes one fact keyed on the symbol's
  canonical identity. `document` is where the occurrence physically is (which is
  the defining file for a definition, but another file for a cross-file
  reference); the symbol's own defining path lives in the key."
  [{:keys [provider-id provider-version source-identity]} document occurrence unit]
  (let [definition? (contains? (:roles occurrence) :definition)]
    {:key {:fact_kind "unit"
           :language "typescript"
           :path (:path unit)
           :owner (:owner unit)
           :symbol (:symbol unit)
           :overload_identity nil
           :dispatch_identity nil}
     :evidence [{:provider_id provider-id
                 :provider_version provider-version
                 :authority "exact"
                 :operation (if definition? "definitions" "references")
                 ;; Freshness is the caller's to establish: this slice records
                 ;; the SCIP claim, the provider adapter runs the stale-artifact
                 ;; gate before the evidence is trusted at exact authority.
                 :freshness "exact"
                 :source_identity source-identity
                 :evidence_location {:path document
                                     :scip_range (:range occurrence)
                                     :scip_roles (vec (sort (map name (:roles occurrence))))}
                 :native_symbol (:symbol occurrence)}]
     :value {:kind (:kind unit)}}))

(defn normalize-index
  "Normalize `semidx.runtime.scip/read-index` output into arbitration facts.

  `opts`:
  - `:provider-id` / `:provider-version` — evidence provenance (defaults
    `\"scip-typescript\"` / `\"1\"`).
  - `:source-identity` — either one identity map applied to every fact, or a
    function of a document's `relative-path` returning that document's identity
    map. ADR-046 requires an anchor (`content_digest` / `document_version` /
    `revision`) for the `exact` authority these facts carry; supplying an
    unanchored identity is a caller error that `fact-arbitration` will reject.

  Returns `{:facts [...] :unmapped [...]}`. `:unmapped` lists every SCIP symbol
  occurrence that was deliberately not turned into a fact, each with a `:reason`."
  [scip-index {:keys [provider-id provider-version source-identity]
               :or {provider-id default-provider-id
                    provider-version default-provider-version}}]
  (let [identity-fn (if (fn? source-identity)
                      source-identity
                      (constantly (or source-identity {})))]
    (reduce
     (fn [acc {:keys [relative-path occurrences]}]
       (let [context {:provider-id provider-id
                      :provider-version provider-version
                      :source-identity (identity-fn relative-path)}]
         (reduce
          (fn [acc occurrence]
            (let [unit (scip-symbol->unit (parse-scip-symbol (:symbol occurrence)))]
              (if (:unmapped unit)
                (update acc :unmapped conj
                        {:native_symbol (:symbol occurrence)
                         :document relative-path
                         :range (:range occurrence)
                         :reason (:unmapped unit)})
                (update acc :facts conj
                        (occurrence->fact context relative-path occurrence unit)))))
          acc
          occurrences)))
     {:facts [] :unmapped []}
     (:documents scip-index))))
