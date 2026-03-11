(ns semantic-code-indexing.typescript-onboarding-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is]]
            [semantic-code-indexing.core :as sci]))

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(deftest typescript-adapter-onboarding-regression-test
  (let [tmp-root (str (java.nio.file.Files/createTempDirectory "sci-typescript-onboarding-test" (make-array java.nio.file.attribute.FileAttribute 0)))
        _ (write-file! tmp-root "src/example/normalize.ts"
                       "export function normalizeOrder(orderId: string): string {\n  return (orderId || \"\").trim().toLowerCase();\n}\n")
        _ (write-file! tmp-root "src/example/main.ts"
                       "import { normalizeOrder } from \"./normalize\";\n\nexport function processMain(orderId: string): string {\n  return normalizeOrder(orderId);\n}\n")
        index (sci/create-index {:root_path tmp-root})
        result (sci/resolve-context-detail index
                                    {:api_version "1.0"
                                     :schema_version "1.0"
                                     :intent {:purpose "code_understanding"
                                              :details "Locate TypeScript processMain function."}
                                     :targets {:symbols ["src.example.main/processMain"]
                                               :paths ["src/example/main.ts"]}
                                     :constraints {:token_budget 1000
                                                   :max_raw_code_level "enclosing_unit"
                                                   :freshness "current_snapshot"}
                                     :hints {:prefer_definitions_over_callers true}
                                     :options {:include_tests false
                                               :include_impact_hints true
                                               :allow_raw_code_escalation false}
                                     :trace {:trace_id "55555555-5555-4555-8555-555555555555"
                                             :request_id "typescript-onboarding-test-001"
                                             :actor_id "test_runner"}})]
    (is (= "typescript" (get-in index [:files "src/example/main.ts" :language])))
    (is (= "full" (get-in index [:files "src/example/main.ts" :parser_mode])))
    (is (some #(= "src.example.main/processMain" (:symbol %))
              (get-in result [:context_packet :relevant_units])))))
