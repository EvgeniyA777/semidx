(ns semidx.runtime.providers-test
  "Stage 2 (plans/018) provider catalog: descriptors, status probes, and the
  role functions that turn a parse into facts."
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest testing is]]
            [semidx.runtime.fact-arbitration :as fa]
            [semidx.runtime.languages.shared :as shared]
            [semidx.runtime.providers :as providers]))

(def ^:private java-root "fixtures/provider-authority/corpus/java")
(def ^:private java-path "src/example/OrderService.java")
(def ^:private ts-root "fixtures/provider-authority/corpus/typescript")
(def ^:private ts-path "src/orders.ts")

(defn- lines-for [root path]
  (shared/slurp-lines (io/file root path)))

(defn- run [provider-id root path]
  (providers/run-provider provider-id
                          {:root_path root
                           :path path
                           :lines (lines-for root path)
                           :parser_opts {}}))

(deftest descriptors-are-serializable-data-test
  (testing "the catalog holds data, not functions, so it can be stored and diffed"
    (is (= providers/descriptors (read-string (pr-str providers/descriptors))))))

(deftest selectors-choose-providers-by-path-test
  (is (= #{"java-tree-sitter" "java-regex"}
         (set (map :provider_id (providers/descriptors-for java-path)))))
  (is (= #{"typescript-tree-sitter" "typescript-regex"}
         (set (map :provider_id (providers/descriptors-for ts-path)))))
  (is (empty? (providers/descriptors-for "src/main.py")))
  (testing "an operation the catalog does not claim selects nothing"
    (is (empty? (providers/descriptors-for java-path :type_hierarchy)))))

(deftest regex-providers-are-always-ready-and-never-exact-test
  (let [status (providers/provider-status "java-regex")]
    (is (= "ready" (:state status)))
    (is (empty? (:reason_codes status))))
  (testing "ADR-046: a lexical provider may not claim exact for any operation"
    (doseq [descriptor providers/descriptors
            :when (= "lexical" (:classification descriptor))
            [operation authority] (:operation_capabilities descriptor)]
      (is (not= "exact" authority)
          (str (:provider_id descriptor) " claims exact for " operation)))))

(deftest tree-sitter-status-names-what-is-missing-test
  (let [status (providers/provider-status "java-tree-sitter" {})]
    (is (contains? #{"ready" "unavailable"} (:state status)))
    (when (= "unavailable" (:state status))
      (is (seq (:reason_codes status))
          "an unavailable provider must say which prerequisite is missing")
      (is (every? #{"tree_sitter_cli_missing" "tree_sitter_grammar_missing"}
                  (:reason_codes status))))))

(deftest unknown-provider-is-refused-not-guessed-test
  (is (= "unavailable" (:state (providers/provider-status "scip-java"))))
  (is (= ["unknown_provider"] (:reason_codes (providers/provider-status "scip-java"))))
  (is (thrown? clojure.lang.ExceptionInfo
               (providers/run-provider "scip-java" {:path java-path :lines []}))))

(deftest java-facts-commit-arity-only-per-variant-c-test
  (let [{:keys [facts]} (run "java-regex" java-root java-path)
        handles (filter #(= "example.OrderService#handle" (get-in % [:key :symbol])) facts)]
    (is (= 4 (count facts)))
    (testing "the heuristic tier commits arity and never a typed signature"
      (doseq [fact facts]
        (let [overload (get-in fact [:key :overload_identity])]
          (is (= "arity_only" (:signature_precision overload)))
          (is (nil? (:signature_key overload)))
          (is (number? (:arity overload))))))
    (testing "distinct overloads of one method stay distinct facts"
      (is (= 2 (count handles)))
      (is (= #{1 2} (set (map #(get-in % [:key :overload_identity :arity]) handles))))
      (is (= 2 (count (distinct (map #(fa/canonical-fact-key-id (:key %)) handles))))))))

(deftest typescript-facts-carry-no-overload-identity-test
  (let [{:keys [facts]} (run "typescript-regex" ts-root ts-path)]
    (is (seq facts))
    (testing "TypeScript exposes no arity, and the fixture's origin key has none"
      (is (every? nil? (map #(get-in % [:key :overload_identity]) facts))))
    (is (some #(= "src.orders/normalize" (get-in % [:key :symbol])) facts))))

(deftest evidence-is-anchored-and-classified-test
  (let [{:keys [facts]} (run "java-regex" java-root java-path)
        evidence (first (:evidence (first facts)))]
    (testing "regex evidence is heuristic, as ADR-046 requires"
      (is (= "heuristic" (:authority evidence))))
    (testing "evidence is anchored to the content that produced it"
      (is (re-find #"^sha256:" (get-in evidence [:source_identity :content_digest])))
      (is (fa/anchored-source-identity? (:source_identity evidence))))
    (testing "the provider's native spelling is retained as evidence only"
      (is (= "example.OrderService#OrderService" (:native_symbol evidence)))
      (is (not (contains? (:key (first facts)) :native_symbol))))
    (testing "every emitted evidence record is valid on its own terms"
      (doseq [fact facts
              ev (:evidence fact)]
        (is (empty? (fa/fact-evidence-errors (fa/normalize-fact-evidence ev))))))))

(deftest content-digest-tracks-content-test
  (is (= (providers/content-digest ["a" "b"]) (providers/content-digest ["a" "b"])))
  (is (not= (providers/content-digest ["a" "b"]) (providers/content-digest ["a" "c"]))))
