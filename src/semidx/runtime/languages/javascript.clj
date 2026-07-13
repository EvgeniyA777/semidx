(ns semidx.runtime.languages.javascript
  (:require [semidx.runtime.languages.typescript :as typescript]))

(defn parse-file [root-path path lines parser-opts]
  (-> (typescript/parse-file root-path path lines parser-opts)
      (assoc :language "javascript")))
