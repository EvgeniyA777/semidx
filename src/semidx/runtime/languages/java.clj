(ns semidx.runtime.languages.java
  (:require [semidx.runtime.adapters :as adapters]))

(defn parse-file [root-path path lines parser-opts]
  (adapters/parse-java-file root-path path lines parser-opts))
