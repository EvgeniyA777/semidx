(ns semidx.runtime.capabilities
  (:require [semidx.runtime.language-registry :as registry]))

(def current-capability-version "1.0")

(defn- confidence-ceiling [strength]
  ;; Currently, strength directly dictates the ceiling since it's non-compensating
  strength)

(defn capabilities-payload
  [server-name server-version]
  {:capability_version current-capability-version
   :server {:name server-name
            :version server-version}
   :languages
   (mapv (fn [{:keys [language extensions provider strength]}]
           {:language language
            :extensions extensions
            :provider provider
            :strength strength
            :confidence_ceiling (confidence-ceiling strength)})
         registry/language-lanes)
   :language_policy_options registry/supported-language-order})
