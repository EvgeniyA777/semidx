(ns semidx.runtime.languages.clojure
  (:require [semidx.runtime.adapters :as adapters]))

(defn parse-file [root-path path lines parser-opts]
  (adapters/parse-clojure-file root-path path lines parser-opts))
