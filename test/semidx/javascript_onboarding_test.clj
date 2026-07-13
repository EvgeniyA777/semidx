(ns semidx.javascript-onboarding-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [semidx.core :as sci]))

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(defn- tmp-root [prefix]
  (str (java.nio.file.Files/createTempDirectory
        prefix (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- units-for-path [index path]
  (->> (:unit_order index)
       (map #(get (:units index) %))
       (filter #(= path (:path %)))
       vec))

(defn- provider-for [index path]
  (some->> (get-in index [:workspace_state :files])
           (filter #(= path (:path %)))
           first
           :provider_id))

(defn- unit-id-by-symbol [storage root module symbol]
  (some->> (sci/query-units storage root {:module module :limit 30})
           (filter #(= symbol (:symbol %)))
           first
           :unit_id))

(deftest javascript-adapter-onboarding-regression-test
  (let [root (tmp-root "sci-javascript-onboarding")
        _ (write-file! root "src/example/normalize.js"
                       "export function normalizeOrder(orderId) {\n  return String(orderId || \"\").trim().toLowerCase();\n}\n")
        _ (write-file! root "src/example/main.js"
                       "import { normalizeOrder } from \"./normalize\";\n\nexport const processMain = (orderId) => normalizeOrder(orderId);\n")
        _ (write-file! root "src/example/view.jsx"
                       "import { normalizeOrder } from \"./normalize\";\n\nexport default class OrderView {\n  renderOrder(orderId) {\n    return normalizeOrder(orderId);\n  }\n}\n")
        _ (write-file! root "src/example/object_modes.mjs"
                       "export const formatters = {\n  normalizeObject(orderId) {\n    return String(orderId || \"\").trim();\n  }\n};\n")
        _ (write-file! root "test/example/main.test.js"
                       "import { processMain } from \"../../src/example/main\";\n\nexport function verifiesMain() {\n  return processMain(\" ABC \");\n}\n")
        _ (write-file! root "test/example/legacy_test.cjs"
                       "function testLegacy() {\n  return true;\n}\n")
        storage (sci/in-memory-storage)
        index (sci/create-index {:root_path root :storage storage})
        main-units (units-for-path index "src/example/main.js")
        jsx-units (units-for-path index "src/example/view.jsx")
        object-units (units-for-path index "src/example/object_modes.mjs")
        test-units (concat (units-for-path index "test/example/main.test.js")
                           (units-for-path index "test/example/legacy_test.cjs"))
        normalize-id (unit-id-by-symbol storage root
                                        "src.example.normalize"
                                        "src.example.normalize/normalizeOrder")
        normalize-callers (sci/query-callers storage root normalize-id {:limit 20})]
    (testing "JavaScript is detected, activated, provider-tagged, and parsed"
      (is (= "javascript" (get-in index [:files "src/example/main.js" :language])))
      (is (= "javascript" (get-in index [:files "src/example/view.jsx" :language])))
      (is (= "javascript" (get-in index [:files "src/example/object_modes.mjs" :language])))
      (is (= "javascript" (get-in index [:files "test/example/legacy_test.cjs" :language])))
      (is (= "full" (get-in index [:files "src/example/main.js" :parser_mode])))
      (is (some #{"javascript"} (:detected_languages index)))
      (is (some #{"javascript"} (:active_languages index)))
      (is (= "javascript-native" (provider-for index "src/example/main.js"))))
    (testing "JavaScript parser reuses TypeScript semantics with JavaScript language tags"
      (is (some #(= "src.example.main/processMain" (:symbol %)) main-units))
      (is (every? #(= "javascript" (:language %)) main-units))
      (is (some #(= "src.example.view.OrderView#renderOrder" (:symbol %)) jsx-units))
      (is (some #(= "src.example.object_modes.formatters#normalizeObject" (:symbol %)) object-units))
      (is (some #(and (= "test" (:kind %))
                      (= "test.example.main.test/verifiesMain" (:symbol %)))
                test-units))
      (is (some #(and (= "test" (:kind %))
                      (= "test.example.legacy_test/testLegacy" (:symbol %)))
                test-units)))
    (testing "ESM imports link JavaScript callers to JavaScript callees"
      (is normalize-id)
      (is (some #(= "src.example.main/processMain" (:symbol %)) normalize-callers))
      (is (some #(= "src.example.view.OrderView#renderOrder" (:symbol %)) normalize-callers)))))

(deftest javascript-freshness-regression-test
  (let [root (tmp-root "sci-javascript-freshness")
        _ (write-file! root "src/a.js" "export function a() { return 1; }\n")
        _ (write-file! root "src/b.js" "export function b() { return 2; }\n")
        _ (write-file! root "src/c.js" "export function c() { return 3; }\n")
        storage (sci/in-memory-storage)
        first-index (sci/create-index {:root_path root :storage storage :load_latest true})]
    (testing "unchanged JavaScript workspace reuses the latest snapshot"
      (let [after (sci/create-index {:root_path root :storage storage :load_latest true})]
        (is (= (:snapshot_id first-index) (:snapshot_id after)))
        (is (= "reuse" (get-in after [:index_lifecycle :lifecycle_action])))))
    (testing "JavaScript content changes flow through incremental freshness"
      (write-file! root "src/a.js" "export function a() { return 11; }\n")
      (let [after (sci/create-index {:root_path root :storage storage :load_latest true})]
        (is (= "incremental_update" (get-in after [:index_lifecycle :lifecycle_action])))
        (is (= "javascript" (get-in after [:files "src/a.js" :language])))
        (is (some #{"javascript"} (:active_languages after)))))
    (testing "JavaScript add and delete deltas stay in the JavaScript lane"
      (write-file! root "src/d.js" "export function d() { return 4; }\n")
      (let [added (sci/create-index {:root_path root :storage storage :load_latest true})]
        (is (= "incremental_update" (get-in added [:index_lifecycle :lifecycle_action])))
        (is (contains? (:files added) "src/d.js")))
      (io/delete-file (io/file root "src/c.js"))
      (let [deleted (sci/create-index {:root_path root :storage storage :load_latest true})]
        (is (= "incremental_update" (get-in deleted [:index_lifecycle :lifecycle_action])))
        (is (not (contains? (:files deleted) "src/c.js")))))))

(deftest javascript-language-policy-regression-test
  (let [root (tmp-root "sci-javascript-policy")
        _ (write-file! root "src/app.clj" "(ns app)\n(defn run [] :ok)\n")
        _ (write-file! root "src/intruder.js" "export function intruder() { return 1; }\n")
        storage (sci/in-memory-storage)
        policy {:allow_languages ["clojure"]}
        index (sci/create-index {:root_path root
                                 :storage storage
                                 :load_latest true
                                 :language_policy policy})]
    (testing "full builds exclude JavaScript when policy allows only Clojure"
      (is (= ["clojure"] (:active_languages index)))
      (is (contains? (:files index) "src/app.clj"))
      (is (not (contains? (:files index) "src/intruder.js"))))
    (testing "incremental freshness does not pull newly added JavaScript into a Clojure-only index"
      (write-file! root "src/later.js" "export function later() { return 2; }\n")
      (let [after (sci/create-index {:root_path root
                                     :storage storage
                                     :load_latest true
                                     :language_policy policy})]
        (is (= ["clojure"] (:active_languages after)))
        (is (not (contains? (:files after) "src/later.js")))))))

(deftest javascript-typescript-cross-language-retrieval-test
  (let [root (tmp-root "sci-javascript-typescript-cross")
        _ (write-file! root "src/example/normalize.ts"
                       "export function normalizeOrder(orderId: string): string {\n  return (orderId || \"\").trim();\n}\n")
        _ (write-file! root "src/example/main.js"
                       "import { normalizeOrder } from \"./normalize\";\n\nexport function processMain(orderId) {\n  return normalizeOrder(orderId);\n}\n")
        storage (sci/in-memory-storage)
        index (sci/create-index {:root_path root :storage storage})
        normalize-id (unit-id-by-symbol storage root
                                        "src.example.normalize"
                                        "src.example.normalize/normalizeOrder")
        callers (sci/query-callers storage root normalize-id {:limit 20})
        result (sci/resolve-context-detail
                index
                {:api_version "1.0"
                 :schema_version "1.0"
                 :intent {:purpose "code_understanding"
                          :details "Locate JavaScript processMain caller for TypeScript normalizeOrder."}
                 :targets {:symbols ["src.example.main/processMain"]
                           :paths ["src/example/main.js"]}
                 :constraints {:token_budget 1200
                               :language_allowlist ["javascript" "typescript"]
                               :max_raw_code_level "enclosing_unit"
                               :freshness "current_snapshot"}
                 :hints {:prefer_definitions_over_callers true
                         :preferred_modules ["src.example.main"]}
                 :options {:include_tests true
                           :include_impact_hints true
                           :allow_raw_code_escalation false}
                 :trace {:trace_id "77777777-7777-4777-8777-777777777777"
                         :request_id "javascript-cross-language-test-001"
                         :actor_id "test_runner"}})]
    (is normalize-id)
    (is (some #(= "src.example.main/processMain" (:symbol %)) callers))
    (is (some #(= "src.example.main/processMain" (:symbol %))
              (get-in result [:context_packet :relevant_units])))))
