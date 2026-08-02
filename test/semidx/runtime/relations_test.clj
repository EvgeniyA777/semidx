(ns semidx.runtime.relations-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [semidx.core :as sci]
            [semidx.runtime.relations :as relations]))

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(defn- sample-root! []
  (let [root (str (java.nio.file.Files/createTempDirectory "semidx-relations" (make-array java.nio.file.attribute.FileAttribute 0)))]
    (write-file! root "src/my/app/core.clj" "(ns my.app.core)\n(defn run [] :ok)\n")
    root))

(deftest normalize-relation-adds-deterministic-identity-and-defaults-test
  (let [relation {:source_unit_id " unit:source "
                  :target_unit_ids ["unit:target" "unit:target" nil ""]
                  :relation_type " dataflow/returns-call-result "
                  :evidence_quality "high"
                  :provenance {:producer "test"}}
        relation-a (assoc relation :provenance (array-map :z 2 :a (array-map :b 1 :a 0)))
        relation-b (assoc relation :provenance (array-map :a (array-map :a 0 :b 1) :z 2))
        normalized (relations/normalize-relation relation)
        normalized-again (relations/normalize-relation relation)
        normalized-a (relations/normalize-relation relation-a)
        normalized-b (relations/normalize-relation relation-b)]
    (is (= (:relation_id normalized) (:relation_id normalized-again)))
    (is (= (:relation_id normalized-a) (:relation_id normalized-b)))
    (is (= "v1" (:relation_schema_version normalized)))
    (is (= "unit:source" (:source_unit_id normalized)))
    (is (= ["unit:target"] (:target_unit_ids normalized)))
    (is (= "resolved" (:resolution_status normalized)))
    (is (relations/valid-relation? normalized))))

(deftest relation-id-preserves-dataflow-argument-payload-test
  (let [base {:source_unit_id "unit:wrapper"
              :target_key "save!"
              :target_unit_ids ["unit:save"]
              :relation_type "dataflow/passes-argument"
              :resolution_status "resolved"
              :evidence_quality "medium"
              :evidence_location {:start_line 10}
              :provenance {:producer "test"}}
        first-arg (relations/normalize-relation (assoc base :local_name "order" :arg_index 0))
        second-arg (relations/normalize-relation (assoc base :local_name "client" :arg_index 1))]
    (is (not= (:relation_id first-arg) (:relation_id second-arg)))))

(deftest index-relations-builds-forward-and-reverse-indexes-test
  (let [resolved (relations/normalize-relation
                  {:source_unit_id "unit:wrapper"
                   :target_unit_ids ["unit:callee"]
                   :relation_type "dataflow/local-binding-call-result"
                   :evidence_quality "medium"
                   :provenance {:producer "test"}})
        unresolved (relations/normalize-relation
                    {:source_unit_id "unit:wrapper"
                     :target_key "my.app/missing"
                     :relation_type "dataflow/passes-argument"
                     :resolution_status "unresolved"
                     :evidence_quality "low"
                     :provenance {:producer "test"}})
        indexed (relations/index-relations [unresolved resolved])]
    (testing "relations are keyed by deterministic relation id"
      (is (= #{(:relation_id resolved) (:relation_id unresolved)}
             (set (keys (:relations indexed))))))
    (testing "forward index is keyed by source unit"
      (is (= #{(:relation_id resolved) (:relation_id unresolved)}
             (get (:relation_forward_index indexed) "unit:wrapper"))))
    (testing "reverse index includes resolved unit targets and unresolved target keys"
      (is (= #{(:relation_id resolved)}
             (get (:relation_reverse_index indexed) "unit:callee")))
      (is (= #{(:relation_id unresolved)}
             (get (:relation_reverse_index indexed) "my.app/missing"))))))

(deftest create-index-attaches-empty-relation-indexes-test
  (let [index (sci/create-index {:root_path (sample-root!)})]
    (is (= {} (:relations index)))
    (is (= {} (:relation_forward_index index)))
    (is (= {} (:relation_reverse_index index)))
    (is (map? (:callers_index index)))
    (is (map? (:callees_index index)))))

(deftest relation-id-stable-across-resolution-and-evidence-test
  (testing "identity derives only from stable semantic fields; resolving an
  unresolved fact and attaching richer evidence keeps one relation_id"
    (let [semantic {:source_unit_id "unit:wrapper"
                    :target_key "save!"
                    :relation_type "dataflow/passes-argument"
                    :local_name "order"
                    :arg_index 0}
          unresolved (relations/normalize-relation
                      (assoc semantic
                             :resolution_status "unresolved"
                             :evidence_quality "low"))
          resolved (relations/normalize-relation
                    (assoc semantic
                           :target_unit_ids ["unit:save"]
                           :resolution_status "resolved"
                           :evidence_quality "high"
                           :evidence_location {:start_line 10}
                           :provenance {:producer "scip"}))]
      (is (= (:relation_id unresolved) (:relation_id resolved)))
      (is (relations/valid-relation? unresolved))
      (is (relations/valid-relation? resolved)))))

(deftest relation-validation-surfaces-structured-diagnostics-test
  (let [ok (relations/normalize-relation
            {:source_unit_id "unit:src"
             :target_unit_ids ["unit:dst"]
             :relation_type "dataflow/returns-call-result"
             :evidence_quality "medium"})
        unknown-type (relations/normalize-relation
                      {:source_unit_id "unit:other"
                       :target_unit_ids ["unit:dst"]
                       :relation_type "bogus/type"
                       :evidence_quality "medium"})
        resolved-no-targets (assoc ok :resolution_status "resolved" :target_unit_ids [])
        {:keys [relations diagnostics]}
        (relations/normalize-relations-with-diagnostics
         [ok unknown-type resolved-no-targets])
        codes (set (mapcat #(map :code (:errors %)) diagnostics))]
    (testing "valid facts pass and invalid facts are excluded"
      (is (relations/valid-relation? ok))
      (is (not (relations/valid-relation? unknown-type)))
      (is (= [(:relation_id ok)] (mapv :relation_id relations))))
    (testing "invalid facts are surfaced as structured diagnostics, not dropped"
      (is (= 2 (count diagnostics)))
      (is (contains? codes :invalid-relation-type))
      (is (contains? codes :resolved-without-targets)))))

(deftest index-relations-surfaces-invalid-fact-diagnostics-test
  (let [valid (relations/normalize-relation
               {:source_unit_id "unit:src"
                :target_unit_ids ["unit:dst"]
                :relation_type "dataflow/returns-call-result"
                :evidence_quality "medium"})
        invalid (relations/normalize-relation
                 {:source_unit_id "unit:other"
                  :target_unit_ids ["unit:dst"]
                  :relation_type "bogus/type"
                  :evidence_quality "medium"})
        indexed (relations/index-relations [valid invalid])]
    (is (= #{(:relation_id valid)} (set (keys (:relations indexed)))))
    (is (= 1 (count (:relation_diagnostics indexed))))
    (is (= :invalid-relation-type
           (-> indexed :relation_diagnostics first :errors first :code)))))
