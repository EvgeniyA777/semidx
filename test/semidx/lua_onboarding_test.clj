(ns semidx.lua-onboarding-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is]]
            [semidx.core :as sci]))

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(deftest lua-adapter-onboarding-regression-test
  (let [tmp-root (str (java.nio.file.Files/createTempDirectory "sci-lua-onboarding-test" (make-array java.nio.file.attribute.FileAttribute 0)))
        _ (write-file! tmp-root "app/helpers.lua"
                       "local M = {}\n\nfunction M.normalize(value)\n  return value\nend\n\nreturn M\n")
        _ (write-file! tmp-root "app/main.lua"
                       "local helpers = require(\"app.helpers\")\n\nlocal M = {}\n\nfunction M.run(value)\n  return helpers.normalize(value)\nend\n\nreturn M\n")
        index (sci/create-index {:root_path tmp-root})
        result (sci/resolve-context-detail index
                                           {:api_version "1.0"
                                            :schema_version "1.0"
                                            :intent {:purpose "code_understanding"
                                                     :details "Locate Lua run function."}
                                            :targets {:symbols ["app.main/run"]
                                                      :paths ["app/main.lua"]}
                                            :constraints {:token_budget 1000
                                                          :max_raw_code_level "enclosing_unit"
                                                          :freshness "current_snapshot"}
                                            :hints {:prefer_definitions_over_callers true}
                                            :options {:include_tests false
                                                      :include_impact_hints true
                                                      :allow_raw_code_escalation false}
                                            :trace {:trace_id "77777777-7777-4777-8777-777777777777"
                                                    :request_id "lua-onboarding-test-001"
                                                    :actor_id "test_runner"}})]
    (is (= "lua" (get-in index [:files "app/main.lua" :language])))
    (is (= "full" (get-in index [:files "app/main.lua" :parser_mode])))
    (is (some #(= "app.main/run" (:symbol %))
              (get-in result [:context_packet :relevant_units])))))

(deftest lua-adapter-method-and-import-linking-regression-test
  (let [tmp-root (str (java.nio.file.Files/createTempDirectory "sci-lua-method-linking-test" (make-array java.nio.file.attribute.FileAttribute 0)))
        _ (write-file! tmp-root "app/helpers.lua"
                       "local M = {}\n\nfunction M.normalize(value)\n  return value\nend\n\nreturn M\n")
        _ (write-file! tmp-root "app/main.lua"
                       "local helpers = require(\"app.helpers\")\n\nlocal M = {}\n\nfunction M:normalize_local(value)\n  return value\nend\n\nfunction M.call_local(self, value)\n  return self:normalize_local(value)\nend\n\nfunction M.run(value)\n  return helpers.normalize(value)\nend\n\nreturn M\n")
        storage (sci/in-memory-storage)
        _index (sci/create-index {:root_path tmp-root :storage storage})
        helper-id (some->> (sci/query-units storage tmp-root {:module "app.helpers" :limit 20})
                           (filter #(= "app.helpers/normalize" (:symbol %)))
                           first
                           :unit_id)
        method-id (some->> (sci/query-units storage tmp-root {:module "app.main" :limit 20})
                           (filter #(= "app.main#normalize_local" (:symbol %)))
                           first
                           :unit_id)
        helper-callers (sci/query-callers storage tmp-root helper-id {:limit 20})
        method-callers (sci/query-callers storage tmp-root method-id {:limit 20})]
    (is helper-id)
    (is method-id)
    (is (some #(= "app.main/run" (:symbol %)) helper-callers))
    (is (some #(= "app.main/call_local" (:symbol %)) method-callers))))
