(ns semidx.runtime.fact-arbitration-test
  "Stage 1 (plans/018, ADR-046) tests for the provider-neutral CanonicalFactKey
  (Variant C) and the deterministic same-key arbitration kernel. Scenarios are
  grounded in the Stage 0 identity fixtures under
  fixtures/provider-authority/identity/."
  (:require [clojure.test :refer [deftest testing is]]
            [semidx.runtime.fact-arbitration :as fa]))

;; --- Fixtures (mirror fixtures/provider-authority/identity) ---

(defn- unit-key [overload]
  {:fact_kind "unit"
   :language "java"
   :path "src/example/OrderService.java"
   :owner "example.OrderService"
   :symbol "example.OrderService#handle"
   :overload_identity overload})

(def regex-handle1
  {:key (unit-key {:arity 1 :signature_precision "arity_only"})
   :evidence [{:provider_id "java-regex" :authority "heuristic" :freshness "unknown"}]})

(def treesitter-handle1
  {:key (unit-key {:arity 1 :signature_precision "arity_only"})
   :evidence [{:provider_id "java-tree-sitter" :authority "structural" :freshness "unknown"}]})

(def scip-handle1
  {:key (unit-key {:arity 1 :signature_precision "typed" :signature_key "java.lang.String"})
   :evidence [{:provider_id "scip-java" :authority "exact" :freshness "exact"}]})

(def lsp-handle1
  {:key (unit-key {:arity 1 :signature_precision "typed" :signature_key "java.lang.String"})
   :evidence [{:provider_id "java-lsp" :authority "exact" :freshness "exact"}]})

(def scip-handle2
  {:key (unit-key {:arity 2 :signature_precision "typed" :signature_key "java.lang.String,int"})
   :evidence [{:provider_id "scip-java" :authority "exact" :freshness "exact"}]})

(def scip-handle1-int
  {:key (unit-key {:arity 1 :signature_precision "typed" :signature_key "int"})
   :evidence [{:provider_id "scip-java" :authority "exact" :freshness "exact"}]})

;; --- CanonicalFactKey identity ---

(deftest core-key-ignores-provider-spelling-and-map-order
  (testing "arity_only and typed spellings of the same overload share one core key id"
    (is (= (fa/canonical-fact-key-id (:key regex-handle1))
           (fa/canonical-fact-key-id (:key scip-handle1)))))
  (testing "map entry order does not change the key id"
    (let [a {:fact_kind "unit" :language "java" :path "p" :owner "O" :symbol "O#h"
             :overload_identity {:arity 1 :signature_precision "arity_only"}}
          b {:symbol "O#h" :owner "O" :overload_identity {:signature_precision "arity_only" :arity 1}
             :path "p" :language "java" :fact_kind "unit"}]
      (is (= (fa/canonical-fact-key-id a) (fa/canonical-fact-key-id b))))))

(deftest distinct-symbols-do-not-collide
  (testing "same legacy signature spelling, different owner/symbol => distinct key"
    (let [handle {:fact_kind "unit" :language "java" :path "src/example/OrderService.java"
                  :owner "example.OrderService" :symbol "example.OrderService#handle"
                  :overload_identity {:arity 1 :signature_precision "arity_only"}}
          validate {:fact_kind "unit" :language "java" :path "src/example/Validator.java"
                    :owner "example.Validator" :symbol "example.Validator#validate"
                    :overload_identity {:arity 1 :signature_precision "arity_only"}}]
      (is (not= (fa/canonical-fact-key-id handle)
                (fa/canonical-fact-key-id validate))))))

(deftest distinct-arities-stay-distinct
  (is (not= (fa/canonical-fact-key-id (:key scip-handle1))
            (fa/canonical-fact-key-id (:key scip-handle2)))))

;; --- Arbitration: common case ---

(deftest same-overload-across-four-providers-merges-to-one-exact-fact
  (let [{:keys [facts diagnostics]}
        (fa/arbitrate-facts [regex-handle1 treesitter-handle1 scip-handle1 lsp-handle1])]
    (is (= 1 (count facts)))
    (is (empty? diagnostics))
    (let [f (first facts)]
      (is (= "exact" (:authority f)) "strongest authority wins")
      (is (= "typed" (:signature_precision f)))
      (is (= "java.lang.String" (:signature_key f)))
      (is (= #{"java-regex" "java-tree-sitter" "scip-java" "java-lsp"}
             (set (map :provider_id (:evidence f))))
          "all provider evidence is retained"))))

(deftest common-case-identity-is-stable-when-typed-evidence-arrives
  (testing "Variant C invariant: a regex-only fact keeps its identity after SCIP attaches"
    (let [id-regex (:fact_identity (first (:facts (fa/arbitrate-facts [regex-handle1]))))
          id-merged (:fact_identity (first (:facts (fa/arbitrate-facts [regex-handle1 scip-handle1]))))]
      (is (= id-regex id-merged)))))

;; --- Arbitration: same-arity overloads (F1a) ---

(deftest distinct-same-arity-typed-overloads-split
  (let [{:keys [facts diagnostics]} (fa/arbitrate-facts [scip-handle1 scip-handle1-int])]
    (is (= 2 (count facts)))
    (is (empty? diagnostics))
    (is (apply distinct? (map :fact_identity facts)) "split facts have distinct identity")
    (is (= #{"int" "java.lang.String"} (set (map :signature_key facts))))))

(deftest arity-only-evidence-under-same-arity-overloads-is-ambiguous
  (let [{:keys [facts diagnostics]}
        (fa/arbitrate-facts [scip-handle1 scip-handle1-int regex-handle1])]
    (is (= 2 (count facts)) "arity-only heuristic is not attributed to a specific overload")
    (is (= [:arity_ambiguous_heuristic] (map :code diagnostics))
        "F1a: unattributable arity-only evidence is surfaced, not silently merged")))

;; --- Authority + determinism ---

(deftest lower-authority-never-outranks-higher
  (let [f (first (:facts (fa/arbitrate-facts [scip-handle1 regex-handle1])))]
    (is (= "exact" (:authority f)))))

(deftest arbitration-is-order-independent
  (let [inputs [regex-handle1 treesitter-handle1 scip-handle1 lsp-handle1 scip-handle1-int]
        base (fa/arbitrate-facts inputs)]
    (is (= base (fa/arbitrate-facts (reverse inputs))))
    (doseq [_ (range 25)]
      (is (= base (fa/arbitrate-facts (shuffle inputs)))))))

;; --- FactEvidence validation (ADR-046) ---

(deftest exact-authority-requires-fresh-identity
  (testing "exact + stale/unknown freshness is rejected"
    (is (= [:exact-without-fresh-identity]
           (map :code (fa/fact-evidence-errors
                       (fa/normalize-fact-evidence
                        {:provider_id "scip" :authority "exact" :freshness "stale"})))))
    (is (empty? (fa/fact-evidence-errors
                 (fa/normalize-fact-evidence
                  {:provider_id "scip" :authority "exact" :freshness "exact"}))))))

(deftest heuristic-evidence-is-valid-without-fresh-identity
  (is (empty? (fa/fact-evidence-errors
               (fa/normalize-fact-evidence
                {:provider_id "java-regex" :authority "heuristic" :freshness "unknown"})))))

(deftest evidence-requires-provider-and-known-authority
  (is (= #{:missing-provider-id :invalid-authority}
         (set (map :code (fa/fact-evidence-errors
                          (fa/normalize-fact-evidence
                           {:authority "compiler" :freshness "exact"})))))))

;; --- Relation facts (ADR-039 aligned) ---

(deftest relation-facts-key-on-adr039-identity
  (let [rel-key {:fact_kind "relation"
                 :relation_type "dataflow/passes-argument"
                 :source_unit_key {:language "java" :symbol "example.OrderService#handle"}
                 :target_key {:language "java" :symbol "example.Validator#validate"}
                 :flow_identity {:arg_index 0}}
        a (fa/arbitrate-facts [{:key rel-key
                                :evidence [{:provider_id "scip-java" :authority "exact" :freshness "exact"}]}
                               {:key rel-key
                                :evidence [{:provider_id "java-regex" :authority "heuristic" :freshness "unknown"}]}])]
    (is (= 1 (count (:facts a))) "same relation identity from two providers merges to one fact")
    (is (= "exact" (:authority (first (:facts a)))))))
