(ns semidx.test-runner-test
  (:require [clojure.test :refer [deftest is testing]]
            [semidx.test-runner :as test-runner]))

(defn- thrown-ex-data [f]
  (try
    (f)
    nil
    (catch clojure.lang.ExceptionInfo ex
      (ex-data ex))))

(deftest selected-test-namespaces-defaults-to-discovery-test
  (with-redefs [test-runner/discover-test-namespaces
                (constantly ['semidx.alpha-test 'semidx.beta-test])]
    (is (= ['semidx.alpha-test 'semidx.beta-test]
           (test-runner/selected-test-namespaces [])))))

(deftest selected-test-namespaces-supports-short-selector-test
  (is (= ['semidx.runtime.capabilities-test]
         (test-runner/selected-test-namespaces
          ["-n" "semidx.runtime.capabilities-test"]))))

(deftest selected-test-namespaces-supports-long-selector-test
  (is (= ['semidx.runtime.http-test]
         (test-runner/selected-test-namespaces
          ["--namespace" "semidx.runtime.http-test"]))))

(deftest selected-test-namespaces-preserves-repeated-selector-order-test
  (is (= ['semidx.runtime.capabilities-test
          'semidx.runtime.http-test]
         (test-runner/selected-test-namespaces
          ["-n" "semidx.runtime.capabilities-test"
           "--namespace" "semidx.runtime.http-test"]))))

(deftest selected-test-namespaces-rejects-unknown-args-test
  (is (= {:type :invalid_test_runner_args
          :argument "--bad"
          :reason :unknown_argument}
         (thrown-ex-data
          #(test-runner/selected-test-namespaces ["--bad"])))))

(deftest selected-test-namespaces-rejects-missing-values-test
  (testing "missing terminal value"
    (is (= {:type :invalid_test_runner_args
            :argument "-n"
            :reason :missing_namespace_value}
           (thrown-ex-data
            #(test-runner/selected-test-namespaces ["-n"])))))
  (testing "next selector is not accepted as a namespace value"
    (is (= {:type :invalid_test_runner_args
            :argument "-n"
            :reason :missing_namespace_value}
           (thrown-ex-data
            #(test-runner/selected-test-namespaces
              ["-n" "--namespace" "semidx.runtime.http-test"]))))))
