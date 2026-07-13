(ns semidx.test-runner
  (:require [clojure.test :as t]
            [semidx.evaluation-test]
            [semidx.mcp-http-server-test]
            [semidx.mcp-server-test]
            [semidx.policy-governance-test]
            [semidx.repo-identity-test]
            [semidx.runtime-grpc-test]
            [semidx.runtime-http-test]
            [semidx.lua-onboarding-test]
            [semidx.html-onboarding-test]
            [semidx.css-onboarding-test]
            [semidx.storage-test]
            [semidx.typescript-onboarding-test]
            [semidx.runtime-test]
            [semidx.usage-metrics-test]
            [semidx.freshness-baseline-test]
            [semidx.workspace-state-test]
            [semidx.freshness-test]
            [semidx.freshness-regression-test]))

(defn -main [& _]
  (let [result (t/run-tests 'semidx.mcp-server-test
                            'semidx.mcp-http-server-test
                            'semidx.evaluation-test
                            'semidx.policy-governance-test
                            'semidx.repo-identity-test
                            'semidx.runtime-test
                            'semidx.runtime-grpc-test
                            'semidx.runtime-http-test
                            'semidx.lua-onboarding-test
                            'semidx.html-onboarding-test
                            'semidx.css-onboarding-test
                            'semidx.storage-test
                            'semidx.typescript-onboarding-test
                            'semidx.usage-metrics-test
                            'semidx.freshness-baseline-test
                            'semidx.workspace-state-test
                            'semidx.freshness-test
                            'semidx.freshness-regression-test)
        failures (+ (:fail result) (:error result))]
    (System/exit (if (zero? failures) 0 1))))
