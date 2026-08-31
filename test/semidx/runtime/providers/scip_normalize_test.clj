(ns semidx.runtime.providers.scip-normalize-test
  "Stage 3 (plans/018, ADR-046) tests for SCIP -> CanonicalFactKey normalization.

  Three layers:

  1. `parse-scip-symbol` against hand-written SCIP symbol strings.
  2. `scip-symbol->unit` — the moniker -> semidx spelling bridge.
  3. `normalize-index` over the committed real artifact
     `typescript-corpus.scrubbed.scip`, checked against the Stage 0 identity
     fixture and the arbitration kernel."
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [semidx.runtime.fact-arbitration :as fa]
            [semidx.runtime.providers.scip-normalize :as sn]
            [semidx.runtime.scip :as scip]))

(def ^:private fixture-scip
  "fixtures/provider-authority/scip/typescript-corpus.scrubbed.scip")

(def ^:private anchored-identity
  {:content_digest "sha256:corpus-fixture" :revision "test-revision"})

;; --- parse-scip-symbol ---------------------------------------------------

(deftest parses-the-scip-symbol-grammar
  (testing "package fields plus namespace/method descriptors"
    (is (= {:scheme "scip-typescript" :manager "npm" :package-name "." :version "."
            :descriptors [{:kind :namespace :name "src"}
                          {:kind :namespace :name "orders.ts"}
                          {:kind :method :name "normalize" :disambiguator ""}]}
           (sn/parse-scip-symbol "scip-typescript npm . . src/`orders.ts`/normalize()."))))

  (testing "a type descriptor before the method"
    (is (= [{:kind :namespace :name "src"}
            {:kind :namespace :name "orders.ts"}
            {:kind :type :name "OrderService"}
            {:kind :method :name "handle" :disambiguator ""}]
           (:descriptors (sn/parse-scip-symbol
                          "scip-typescript npm . . src/`orders.ts`/OrderService#handle().")))))

  (testing "backtick-escaped constructor name"
    (is (= {:kind :method :name "<constructor>" :disambiguator ""}
           (last (:descriptors (sn/parse-scip-symbol
                                "scip-typescript npm . . src/`orders.ts`/OrderService#`<constructor>`()."))))))

  (testing "a trailing parameter descriptor"
    (is (= {:kind :parameter :name "value"}
           (last (:descriptors (sn/parse-scip-symbol
                                "scip-typescript npm . . src/`orders.ts`/normalize().(value)"))))))

  (testing "a field is a term descriptor"
    (is (= {:kind :term :name "validator"}
           (last (:descriptors (sn/parse-scip-symbol
                                "scip-typescript npm . . src/`orders.ts`/OrderService#validator."))))))

  (testing "an external package keeps its real name and version"
    (let [parsed (sn/parse-scip-symbol
                  "scip-typescript npm typescript 5.9.3 lib/`lib.es5.d.ts`/String#trim().")]
      (is (= "typescript" (:package-name parsed)))
      (is (= "5.9.3" (:version parsed)))))

  (testing "local and empty symbols"
    (is (= {:scheme "local" :local-id "0" :descriptors []}
           (sn/parse-scip-symbol "local 0")))
    (is (= {:error :empty-symbol} (sn/parse-scip-symbol "")))
    (is (= :malformed-symbol (:error (sn/parse-scip-symbol "not a scip symbol")))))

  (testing "a descriptor sequence the reader rejects is an :error, never a throw"
    (doseq [bad ["scip-typescript npm . . src/`orders.ts"          ; unterminated backtick
                 "scip-typescript npm . . src/`orders.ts`/normalize("]] ; malformed method
      (is (= :unparseable-descriptors (:error (sn/parse-scip-symbol bad))) bad)
      (is (string? (:message (sn/parse-scip-symbol bad))) bad))))

;; --- scip-symbol->unit -------------------------------------------------

(defn- unit-of [sym]
  (sn/scip-symbol->unit (sn/parse-scip-symbol sym)))

(deftest bridges-mappable-symbols-onto-semidx-spelling
  (testing "top-level function: <module>/<name>, module from the file path"
    (is (= {:owner "src.orders" :symbol "src.orders/normalize" :kind "function"
            :path "src/orders.ts"}
           (unit-of "scip-typescript npm . . src/`orders.ts`/normalize().")))
    (is (= {:owner "src.orders" :symbol "src.orders/createOrder" :kind "function"
            :path "src/orders.ts"}
           (unit-of "scip-typescript npm . . src/`orders.ts`/createOrder()."))))

  (testing "class method: <module>.<Class>#<method>"
    (is (= {:owner "src.orders.OrderService" :symbol "src.orders.OrderService#handle"
            :kind "function" :path "src/orders.ts"}
           (unit-of "scip-typescript npm . . src/`orders.ts`/OrderService#handle().")))
    (is (= {:owner "src.validator.Validator" :symbol "src.validator.Validator#validate"
            :kind "function" :path "src/validator.ts"}
           (unit-of "scip-typescript npm . . src/`validator.ts`/Validator#validate()."))))

  (testing "a top-level term (const/let) maps as a :kind \"term\" unit"
    ;; scip-typescript spells every top-level binding as a term descriptor,
    ;; whether it holds an arrow function or a plain value.
    (is (= {:owner "src.config" :symbol "src.config/normalize" :kind "term"
            :path "src/config.ts"}
           (unit-of "scip-typescript npm . . src/`config.ts`/normalize."))
        "an arrow-function const still keys on <module>/<name>")
    (is (= {:owner "src.config" :symbol "src.config/VERSION" :kind "term"
            :path "src/config.ts"}
           (unit-of "scip-typescript npm . . src/`config.ts`/VERSION."))
        "a plain value const is an exact-only term unit"))

  (testing "an arrow-function term shares its canonical key with the regex tier"
    (let [u (unit-of "scip-typescript npm . . src/`config.ts`/normalize.")]
      (is (= (fa/canonical-fact-key-id {:fact_kind "unit" :language "typescript"
                                        :path "src/config.ts" :owner "src.config"
                                        :symbol "src.config/normalize" :overload_identity nil})
             (fa/canonical-fact-key-id {:fact_kind "unit" :language "typescript"
                                        :path (:path u) :owner (:owner u)
                                        :symbol (:symbol u) :overload_identity nil}))))))

(deftest records-kinds-semidx-does-not-model-as-unmapped
  (doseq [[reason sym]
          {:type-symbol "scip-typescript npm . . src/`orders.ts`/OrderService#"
           :field-symbol "scip-typescript npm . . src/`orders.ts`/OrderService#validator."
           :constructor-symbol "scip-typescript npm . . src/`orders.ts`/OrderService#`<constructor>`()."
           :non-unit-descriptor "scip-typescript npm . . src/`orders.ts`/normalize().(value)"
           :module-symbol "scip-typescript npm . . src/`orders.ts`/"
           :external-symbol "scip-typescript npm typescript 5.9.3 lib/`lib.es5.d.ts`/String#trim()."
           :local-symbol "local 0"}]
    (is (= reason (:unmapped (unit-of sym))) sym)))

;; --- normalize-index over the real artifact ---------------------------

(deftest normalizes-the-committed-scip-artifact
  (let [{:keys [facts unmapped]}
        (sn/normalize-index (scip/read-index fixture-scip)
                            {:source-identity anchored-identity})]

    (testing "every emitted fact is a well-formed exact-authority unit fact"
      (is (seq facts))
      (is (every? #(= "unit" (get-in % [:key :fact_kind])) facts))
      (is (every? #(= "typescript" (get-in % [:key :language])) facts))
      (is (empty? (mapcat (comp fa/fact-evidence-errors fa/normalize-fact-evidence)
                          (mapcat :evidence facts)))
          "anchored source identity + exact + fresh must validate clean"))

    (testing "SCIP normalizes onto the SAME key the regex tier produces"
      (let [normalize-fact (first (filter #(= "src.orders/normalize"
                                              (get-in % [:key :symbol]))
                                          facts))]
        (is (some? normalize-fact))
        (is (= (fa/canonical-fact-key-id (:key normalize-fact))
               (fa/canonical-fact-key-id {:fact_kind "unit" :language "typescript"
                                          :path "src/orders.ts" :owner "src.orders"
                                          :symbol "src.orders/normalize"
                                          :overload_identity nil})))))

    (testing "the re-export surface: index.ts references resolve to the orders.ts origin"
      (let [normalize-evidence (->> facts
                                    (filter #(= "src.orders/normalize" (get-in % [:key :symbol])))
                                    (mapcat :evidence))]
        (is (= #{"definitions" "references"} (set (map :operation normalize-evidence))))
        (is (= 1 (count (filter #(= "definitions" (:operation %)) normalize-evidence))))
        (is (contains? (set (map (comp :path :evidence_location) normalize-evidence))
                       "src/index.ts")
            "the canonicalize/normalize re-export tokens in index.ts corroborate the origin")))

    (testing "only the kinds semidx models are minted: top-level fns and methods"
      (is (= #{"src.orders/normalize"
               "src.orders/createOrder"
               "src.orders.OrderService#handle"
               "src.validator.Validator#validate"}
             (set (map #(get-in % [:key :symbol]) facts)))
          "class, constructor, field, param, module, and stdlib symbols mint no fact")
      (is (not-any? #(str/starts-with? (str (get-in % [:key :owner])) "src.index") facts)
          "the alias export src/canonicalize is never a SCIP unit fact"))

    (testing "unmapped symbols carry a reason"
      (is (every? :reason unmapped))
      (is (contains? (set (map :reason unmapped)) :external-symbol)))))

(deftest one-malformed-occurrence-does-not-abort-the-index
  (let [{:keys [facts unmapped]}
        (sn/normalize-index
         {:documents [{:relative-path "src/x.ts"
                       :occurrences [{:symbol "scip-typescript npm . . src/`x.ts`/foo()."
                                      :roles #{:definition} :range [1 0 3]}
                                     {:symbol "scip-typescript npm . . src/`x.ts`/bar("
                                      :roles #{} :range [2 0 3]}]}]}
         {:source-identity anchored-identity})]
    (is (= ["src.x/foo"] (map #(get-in % [:key :symbol]) facts))
        "the good occurrence still produces its fact")
    (is (= [:unparseable-descriptors] (map :reason unmapped))
        "the malformed occurrence becomes unmapped, not an exception")))

(deftest scip-and-regex-evidence-merge-into-one-exact-fact
  (let [{:keys [facts]} (sn/normalize-index (scip/read-index fixture-scip)
                                            {:source-identity anchored-identity})
        scip-normalize (filter #(= "src.orders/normalize" (get-in % [:key :symbol])) facts)
        regex-fact {:key {:fact_kind "unit" :language "typescript" :path "src/orders.ts"
                          :owner "src.orders" :symbol "src.orders/normalize"
                          :overload_identity nil}
                    :evidence [{:provider_id "typescript-regex" :authority "heuristic"
                                :freshness "unknown"
                                :native_symbol "src.orders/normalize"}]}
        {:keys [facts diagnostics]} (fa/arbitrate-facts (conj (vec scip-normalize) regex-fact))
        merged (first facts)]
    (is (= 1 (count facts)))
    (is (empty? diagnostics))
    (is (= "exact" (:authority merged)) "SCIP exact wins over regex heuristic")
    (is (= #{"scip-typescript" "typescript-regex"}
           (set (map :provider_id (:evidence merged))))
        "both tiers' evidence is retained on the one fact")
    (is (= (:canonical_fact_key_id merged) (:fact_identity merged))
        "Variant C: attaching SCIP evidence does not change the regex-only identity")))

;; --- identity fixture parity -----------------------------------------

(defn- read-identity-fixture [file-name]
  (with-open [rdr (io/reader (io/file "fixtures/provider-authority/identity" file-name))]
    (json/read rdr :key-fn keyword)))

(deftest scip-spelling-matches-the-typescript-re-export-identity-fixture
  (let [fixture (read-identity-fixture "typescript-re-export-canonical-key.json")
        edge (:re_export_edge_must_resolve_to_origin fixture)
        origin (:expected_canonical_key_of_origin edge)
        scip-spelling (->> (:provider_spellings edge)
                           (filter #(= "scip-typescript" (:provider_id %)))
                           first)
        ;; the SCIP native re-export target moniker, mapped by this slice
        mapped (sn/scip-symbol->unit
                (sn/parse-scip-symbol (:native_re_export_target scip-spelling)))]
    (testing "the fixture still describes scip-typescript's verified behaviour"
      (is (false? (:alias_symbol_emitted scip-spelling)))
      (is (false? (:relationship_emitted scip-spelling))))

    (testing "the SCIP moniker resolves to the origin's canonical key, field by field"
      (is (= (:owner origin) (:owner mapped)))
      (is (= (:symbol origin) (:symbol mapped)))
      (is (= (:path origin) (:path mapped)))
      (is (= (fa/canonical-fact-key-id {:fact_kind "unit"
                                        :language (:language origin)
                                        :path (:path origin)
                                        :owner (:owner origin)
                                        :symbol (:symbol origin)
                                        :overload_identity (:overload_identity origin)})
             (fa/canonical-fact-key-id {:fact_kind "unit"
                                        :language "typescript"
                                        :path (:path mapped)
                                        :owner (:owner mapped)
                                        :symbol (:symbol mapped)
                                        :overload_identity nil}))))

    (testing "the alias export stays a distinct identity SCIP never mints"
      (doseq [distinct-fact (:distinct_facts_must_not_merge fixture)
              :let [expected (:expected_canonical_key distinct-fact)]]
        (is (not= (fa/canonical-fact-key-id {:fact_kind "unit" :language "typescript"
                                             :path (:path mapped) :owner (:owner mapped)
                                             :symbol (:symbol mapped) :overload_identity nil})
                  (fa/canonical-fact-key-id {:fact_kind "unit" :language "typescript"
                                             :path (:path expected) :owner (:owner expected)
                                             :symbol (:symbol expected) :overload_identity nil}))
            (str (:fact distinct-fact) " — " (:reason distinct-fact)))))))
