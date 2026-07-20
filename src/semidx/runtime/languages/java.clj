(ns semidx.runtime.languages.java
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [semidx.runtime.languages.shared :as shared]))

(def ^:private java-package-re #"^\s*package\s+([a-zA-Z0-9_\.]+)\s*;")
(def ^:private java-import-re #"^\s*import\s+(?:static\s+)?([a-zA-Z0-9_\.\*]+)\s*;")
(def ^:private java-class-re #"^\s*(?:public\s+)?(?:class|interface|enum)\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s+extends\s+([A-Za-z0-9_\.]+))?")
(def ^:private java-method-re
  #"^\s*(?:(public|private|protected)\s+)?(?:(?:static|final|native|synchronized|abstract|default)\s+)*([A-Za-z0-9_<>,\[\]\.\?]+)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?:\{|throws|;)")
(def ^:private java-constructor-re
  #"^\s*(?:(public|private|protected)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?:\{|throws)")

(def ^:private java-call-stop
  #{"if" "for" "while" "switch" "catch" "return" "throw" "new" "super" "this" "synchronized"})

(defn- trim-signature [line]
  (shared/trim-signature line))

(defn- unit-end-lines [starts total-lines]
  (shared/unit-end-lines starts total-lines))

(defn- tail-token [token]
  (shared/tail-token token))

(defn- safe-line [lines n]
  (shared/safe-line lines n))

(defn- tree-sitter-available? []
  (shared/tree-sitter-available?))

(defn- parser-grammar-path [parser-opts lang]
  (shared/parser-grammar-path parser-opts lang))

(defn- tree-sitter-cst [abs-path grammar-path]
  (shared/tree-sitter-cst abs-path grammar-path))

(defn- add-tree-sitter-diag [parsed enabled? language]
  (shared/add-tree-sitter-diag parsed enabled? language))

(defn- short-hash [s]
  (let [md (java.security.MessageDigest/getInstance "SHA-1")
        bytes (.digest md (.getBytes (str s) java.nio.charset.StandardCharsets/UTF_8))]
    (format "%02x%02x%02x%02x" (aget bytes 0) (aget bytes 1) (aget bytes 2) (aget bytes 3))))

(defn- java-kind
  ([path method-name]
   (java-kind path method-name nil))
  ([path method-name explicit-kind]
   (if explicit-kind
     explicit-kind
     (if (or (str/includes? (str/lower-case path) "/test/")
             (str/ends-with? method-name "Test")
             (str/starts-with? method-name "test"))
       "test"
       "method"))))

(defn- java-args-arity [args-text]
  (let [text (str/trim (or args-text ""))]
    (if (str/blank? text)
      0
      (loop [chars (seq text)
             depth 0
             in-string? false
             escaped? false
             commas 0]
        (if-let [ch (first chars)]
          (cond
            escaped?
            (recur (next chars) depth in-string? false commas)

            in-string?
            (cond
              (= ch \\) (recur (next chars) depth in-string? true commas)
              (= ch \") (recur (next chars) depth false false commas)
              :else (recur (next chars) depth in-string? false commas))

            (= ch \")
            (recur (next chars) depth true false commas)

            (#{\( \[ \< \{} ch)
            (recur (next chars) (inc depth) in-string? false commas)

            (#{\) \] \> \}} ch)
            (recur (next chars) (max 0 (dec depth)) in-string? false commas)

            (and (= ch \,) (zero? depth))
            (recur (next chars) depth in-string? false (inc commas))

            :else
            (recur (next chars) depth in-string? false commas))
          (inc commas))))))

(defn- java-call-details [body]
  (let [text (str body)
        n (count text)]
    (loop [idx 0
           in-string? false
           escaped? false
           details []]
      (if (>= idx n)
        details
        (let [ch (.charAt text idx)]
          (cond
            escaped?
            (recur (inc idx) in-string? false details)

            in-string?
            (cond
              (= ch \\) (recur (inc idx) in-string? true details)
              (= ch \") (recur (inc idx) false false details)
              :else (recur (inc idx) in-string? false details))

            (= ch \")
            (recur (inc idx) true false details)

            (and (= ch \:) (< (inc idx) n) (= (.charAt text (inc idx)) \:))
            (let [prefix (subs text 0 idx)
                  suffix (subs text (+ idx 2))
                  owner (some-> (re-find #"([A-Za-z_][A-Za-z0-9_\.]*)\s*$" prefix) second)
                  method-name (some-> (re-find #"^\s*([A-Za-z_][A-Za-z0-9_]*)" suffix) second)]
              (recur (+ idx 2)
                     in-string?
                     false
                     (if (or (str/blank? owner)
                             (str/blank? method-name)
                             (contains? java-call-stop (str/lower-case method-name)))
                       details
                       (conj details {:token (str owner "#" method-name)
                                      :arity nil
                                      :method_reference true}))))

            (= ch \()
            (let [prefix (subs text 0 idx)
                  token (some-> (re-find #"([A-Za-z_][A-Za-z0-9_\.]*)\s*$" prefix) second)
                  close-idx (loop [j (inc idx)
                                   depth 1
                                   in-string2? false
                                   escaped2? false]
                              (if (>= j n)
                                n
                                (let [ch2 (.charAt text j)]
                                  (cond
                                    escaped2?
                                    (recur (inc j) depth in-string2? false)

                                    in-string2?
                                    (cond
                                      (= ch2 \\) (recur (inc j) depth in-string2? true)
                                      (= ch2 \") (recur (inc j) depth false false)
                                      :else (recur (inc j) depth in-string2? false))

                                    (= ch2 \")
                                    (recur (inc j) depth true false)

                                    (= ch2 \()
                                    (recur (inc j) (inc depth) in-string2? false)

                                    (= ch2 \))
                                    (if (= depth 1)
                                      j
                                      (recur (inc j) (dec depth) in-string2? false))

                                    :else
                                    (recur (inc j) depth in-string2? false)))))
                  args-text (if (< idx close-idx) (subs text (inc idx) close-idx) "")]
              (recur (inc idx)
                     in-string?
                     false
                     (if (or (str/blank? token)
                             (contains? java-call-stop (str/lower-case token)))
                       details
                       (conj details {:token token
                                      :arity (java-args-arity args-text)}))))

            :else
            (recur (inc idx) in-string? false details)))))))

(defn- java-call-arity-index [call-details]
  (reduce (fn [acc {:keys [token arity]}]
            (let [tail (tail-token token)]
              (cond-> acc
                (and (seq token) (number? arity)) (update token (fnil conj #{}) arity)
                (and (seq tail) (not= tail token) (number? arity)) (update tail (fnil conj #{}) arity))))
          {}
          call-details))

(defn- java-call-tokens [call-details]
  (->> call-details
       (map :token)
       (mapcat (fn [token]
                 (if (re-find #"[.#]" (str token))
                   [token]
                   (let [tail (tail-token token)]
                     (cond-> [token]
                       (and tail (not= tail token)) (conj tail))))))
       (remove #(contains? java-call-stop %))
       distinct
       vec))

(defn- java-call-scan-body [lines start-line end-line]
  (let [segment (subvec lines (dec start-line) end-line)
        first-line (first segment)
        stripped-first (if-let [brace-idx (some-> first-line (str/index-of "{"))]
                         (subs first-line (inc brace-idx))
                         "")
        body-lines (cond-> [(or stripped-first "")]
                     (> (count segment) 1) (into (subvec segment 1)))]
    (str/join "\n" body-lines)))

(defn- java-resolve-class-name [pkg imports class-name]
  (let [nm (str/trim (str class-name))]
    (cond
      (str/blank? nm) nil
      (str/includes? nm ".") nm
      :else
      (or (some (fn [imp]
                  (let [candidate (str imp)]
                    (cond
                      (= candidate nm) candidate
                      (str/ends-with? candidate (str "." nm)) candidate
                      (str/ends-with? candidate ".*") (str (subs candidate 0 (- (count candidate) 2)) "." nm)
                      :else nil)))
                imports)
          (when (seq pkg) (str pkg "." nm))
          nm))))

(defn- java-class-spots [pkg imports lines]
  (->> (map-indexed vector lines)
       (keep (fn [[idx line]]
               (when-let [[_ class-name super-name] (re-find java-class-re line)]
                 {:line (inc idx)
                  :class class-name
                  :superclass_module (java-resolve-class-name pkg imports super-name)})))
       vec))

(defn- java-normalized-params [params]
  (-> (or params "")
      str
      (str/replace #"\s+" "")
      (str/replace #",+" ",")
      (str/replace #"^,+|,+$" "")))

(defn- java-param-fragment-from-source [src-lines start-line]
  (let [idx (max 0 (dec start-line))
        window (->> (subvec src-lines idx (min (count src-lines) (+ idx 6)))
                    (str/join " "))]
    (some-> (re-find #"\(([^)]*)\)" window) second)))

(defn- java-method-arity [params]
  (let [p (java-normalized-params params)]
    (if (str/blank? p) 0 (count (str/split p #",")))))

(defn- java-method-unit-id [path symbol params]
  (let [norm (java-normalized-params params)
        arity (java-method-arity norm)
        suffix (if (str/blank? norm)
                 (str "$arity" arity)
                 (str "$arity" arity "$sig" (short-hash norm)))]
    {:unit_id (str path "::" symbol suffix)
     :method_arity arity
     :method_signature_key norm}))

(defn- parse-java-regex [path lines]
  (let [line-count (count lines)
        pkg (some (fn [line] (some-> (re-find java-package-re line) second)) lines)
        imports (->> lines
                     (keep (fn [line] (some-> (re-find java-import-re line) second)))
                     distinct
                     vec)
        class-spots (java-class-spots pkg imports lines)
        methods (->> (map-indexed vector lines)
                     (keep (fn [[idx line]]
                             (let [class-name (->> class-spots
                                                   (filter #(<= (:line %) (inc idx)))
                                                   last
                                                   :class)
                                   super-module (->> class-spots
                                                     (filter #(<= (:line %) (inc idx)))
                                                     last
                                                     :superclass_module)
                                   method-match (re-find java-method-re line)
                                   constructor-match (re-find java-constructor-re line)]
                               (cond
                                 constructor-match
                                 (let [[_ _visibility ctor-name params] constructor-match]
                                   (when (= ctor-name class-name)
                                     {:start-line (inc idx)
                                      :method ctor-name
                                      :params params
                                      :class class-name
                                      :superclass_module super-module
                                      :signature (trim-signature line)
                                      :kind "constructor"}))

                                 method-match
                                 (let [[_ _visibility return-type m params] method-match]
                                   (when-not (contains? java-call-stop (str/lower-case (str return-type)))
                                     {:start-line (inc idx)
                                      :method m
                                      :params params
                                      :class class-name
                                      :superclass_module super-module
                                      :signature (trim-signature line)
                                      :kind nil}))))))
                     vec)
        starts (mapv :start-line methods)
        ends (unit-end-lines starts line-count)
        units (->> (map vector methods ends)
                   (map (fn [[m end-line]]
                          (let [start-line (:start-line m)
                                cls (or (:class m) "UnknownClass")
                                symbol (str (when pkg (str pkg ".")) cls "#" (:method m))
                                {:keys [unit_id method_arity method_signature_key]}
                                (java-method-unit-id path symbol (:params m))
                                body (java-call-scan-body lines start-line end-line)
                                call-details (java-call-details body)]
                            {:unit_id unit_id
                             :kind (java-kind path (:method m) (:kind m))
                             :symbol symbol
                             :path path
                             :module (if pkg (str pkg "." cls) cls)
                             :class_name cls
                             :superclass_module (:superclass_module m)
                             :start_line start-line
                             :end_line end-line
                             :signature (:signature m)
                             :summary (str "method " symbol)
                             :docstring_excerpt nil
                             :imports imports
                             :method_arity method_arity
                             :method_signature_key method_signature_key
                             :calls (java-call-tokens call-details)
                             :call_arity_by_token (java-call-arity-index call-details)
                             :parser_mode "full"})))
                   vec)]
    {:language "java"
     :module pkg
     :imports imports
     :units units
     :diagnostics []
     :parser_mode "full"}))

(defn- node-name-inside [ts-lines node name-marker]
  (->> ts-lines
       (filter #(<= (:start-row node) (:start-row %) (:end-row node)))
       (filter #(< (:indent node) (:indent %)))
       (filter #(and (= "identifier" (:node-type %))
                     (str/includes? (:text %) name-marker)
                     (:value %)))
       (sort-by (juxt :start-row :start-col))
       first
       :value))

(defn- parse-java-tree-sitter [root-path path src-lines parser-opts]
  (let [grammar-path (parser-grammar-path parser-opts :java)
        abs (-> (io/file root-path path) .getCanonicalPath)
        pkg (some (fn [line] (some-> (re-find java-package-re line) second)) src-lines)
        imports (->> src-lines
                     (keep (fn [line] (some-> (re-find java-import-re line) second)))
                     distinct
                     vec)
        class-spots (java-class-spots pkg imports src-lines)]
    (cond
      (not (tree-sitter-available?))
      {:ok? false
       :reason {:code "tree_sitter_unavailable"
                :summary "tree-sitter CLI is unavailable for java tree-sitter parser."}}

      (str/blank? (str grammar-path))
      {:ok? false
       :reason {:code "tree_sitter_missing_grammar"
                :summary "No tree-sitter Java grammar path configured."}}

      :else
      (let [{:keys [ok? lines err]} (tree-sitter-cst abs grammar-path)
            ts-lines lines]
        (if-not ok?
          {:ok? false
           :reason {:code "tree_sitter_parse_failed"
                    :summary (str "tree-sitter parse failed: " (subs (str err) 0 (min 220 (count (str err)))))}}
          (let [classes (->> ts-lines
                             (filter #(= "class_declaration" (:node-type %)))
                             (map (fn [c] (assoc c :class-name (or (node-name-inside ts-lines c "name:") "UnknownClass"))))
                             vec)
                methods (->> ts-lines
                             (filter #(contains? #{"method_declaration" "constructor_declaration"} (:node-type %)))
                             (map (fn [m]
                                    (let [cls (->> classes
                                                   (filter #(<= (:start-row %) (:start-row m) (:end-row %)))
                                                   (sort-by :start-row)
                                                   last
                                                   :class-name)
                                          class-spot (->> class-spots
                                                          (filter #(and (= cls (:class %))
                                                                        (<= (:line %) (inc (:start-row m)))))
                                                          last)
                                          constructor? (= "constructor_declaration" (:node-type m))
                                          method-name (if constructor?
                                                        (or cls "UnknownClass")
                                                        (or (node-name-inside ts-lines m "name:") "unknownMethod"))
                                          body (java-call-scan-body src-lines (inc (:start-row m)) (inc (:end-row m)))
                                          call-details (java-call-details body)]
                                      {:start-line (inc (:start-row m))
                                       :end-line (inc (:end-row m))
                                       :method method-name
                                       :kind (when constructor? "constructor")
                                       :class (or cls "UnknownClass")
                                       :params (java-param-fragment-from-source src-lines (inc (:start-row m)))
                                       :superclass_module (:superclass_module class-spot)
                                       :call_details call-details})))
                             vec)
                units (->> methods
                           (map (fn [{:keys [start-line end-line method kind class call_details params superclass_module]}]
                                  (let [symbol (str (when pkg (str pkg ".")) class "#" method)
                                        {:keys [unit_id method_arity method_signature_key]}
                                        (java-method-unit-id path symbol params)]
                                    {:unit_id unit_id
                                     :kind (java-kind path method kind)
                                     :symbol symbol
                                     :path path
                                     :module (if pkg (str pkg "." class) class)
                                     :class_name class
                                     :superclass_module superclass_module
                                     :start_line start-line
                                     :end_line end-line
                                     :signature (safe-line src-lines start-line)
                                     :summary (str "method " symbol)
                                     :docstring_excerpt nil
                                     :imports imports
                                     :method_arity method_arity
                                     :method_signature_key method_signature_key
                                     :calls (java-call-tokens call_details)
                                     :call_arity_by_token (java-call-arity-index call_details)
                                     :parser_mode "full"})))
                           vec)]
            (if (seq units)
              {:ok? true
               :result {:language "java"
                        :module pkg
                        :imports imports
                        :units units
                        :diagnostics [{:code "tree_sitter_active"
                                       :summary "Java analyzed using tree-sitter CST extraction."}]
                        :parser_mode "full"}}
              {:ok? false
               :reason {:code "tree_sitter_no_units"
                        :summary "tree-sitter did not extract Java units."}})))))))

(defn parse-file [root-path path lines {:keys [java_engine tree_sitter_enabled]
                                             :or {java_engine :regex}
                                             :as parser-opts}]
  (let [engine (if (true? tree_sitter_enabled) :tree-sitter java_engine)
        parsed (if (= engine :tree-sitter)
                 (let [{:keys [ok? result reason]} (parse-java-tree-sitter root-path path lines parser-opts)]
                   (if ok?
                     result
                     (-> (parse-java-regex path lines)
                         (update :diagnostics conj reason))))
                 (parse-java-regex path lines))]
    (add-tree-sitter-diag parsed tree_sitter_enabled "java")))
