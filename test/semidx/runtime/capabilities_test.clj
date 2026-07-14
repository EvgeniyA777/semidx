(ns semidx.runtime.capabilities-test
  (:require [clojure.test :refer [deftest is testing]]
            [malli.core :as m]
            [malli.error :as me]
            [semidx.contracts.schemas :as schemas]
            [semidx.runtime.capabilities :as cap]
            [semidx.runtime.language-registry :as registry]))

(deftest capabilities-payload-test
  (testing "Generates schema-valid capabilities payload with all languages"
    (let [payload (cap/capabilities-payload "test-server" "1.0.0")]
      (is (= "1.0" (:capability_version payload)))
      (is (= "test-server" (get-in payload [:server :name])))
      (is (= "1.0.0" (get-in payload [:server :version])))
      (is (= (count registry/language-lanes) (count (:languages payload))))
      (is (= registry/supported-language-order (:language_policy_options payload)))
      
      (let [schema (get schemas/contracts :example/capabilities)
            explain (m/explain schema payload)]
        (is (nil? explain) (pr-str (when explain (me/humanize explain))))))))
