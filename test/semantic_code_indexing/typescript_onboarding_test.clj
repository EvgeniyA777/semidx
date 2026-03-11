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

(deftest typescript-adapter-import-modes-onboarding-regression-test
  (let [tmp-root (str (java.nio.file.Files/createTempDirectory "sci-typescript-import-modes-test" (make-array java.nio.file.attribute.FileAttribute 0)))
        _ (write-file! tmp-root "src/example/default_normalize.ts"
                       "export default function normalizeDefault(orderId: string): string {\n  return (orderId || \"\").trim().toUpperCase();\n}\n")
        _ (write-file! tmp-root "src/example/helpers.ts"
                       "export function normalizeHelper(orderId: string): string {\n  return (orderId || \"\").trim();\n}\n")
        _ (write-file! tmp-root "src/example/import_modes.ts"
                       "import normalizeDefault from \"./default_normalize\";\nimport { normalizeHelper as namedNormalize } from \"./helpers\";\nimport * as helperNs from \"./helpers\";\n\nexport function processImports(orderId: string): string {\n  namedNormalize(orderId);\n  return normalizeDefault(orderId);\n}\n\nexport const normalizeExpr = function(orderId: string): string {\n  return helperNs.normalizeHelper(orderId);\n};\n")
        storage (sci/in-memory-storage)
        index (sci/create-index {:root_path tmp-root :storage storage})
        helper-units (sci/query-units storage tmp-root {:module "src.example.helpers" :limit 20})
        helper-id (some->> helper-units
                           (filter #(= "src.example.helpers/normalizeHelper" (:symbol %)))
                           first
                           :unit_id)
        helper-callers (sci/query-callers storage tmp-root helper-id {:limit 20})]
    (is (= ["src.example.default_normalize" "src.example.helpers"]
           (get-in index [:files "src/example/import_modes.ts" :imports])))
    (is (some #(= "src.example.import_modes/normalizeExpr" (:symbol %))
              (vals (:units index))))
    (is (some #(= "src.example.import_modes/processImports" (:symbol %))
              helper-callers))
    (is (some #(= "src.example.import_modes/normalizeExpr" (:symbol %))
              helper-callers))))
