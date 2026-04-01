(ns semidx.runtime.languages.python
  (:require [semidx.runtime.adapters :as adapters]))

(defn parse-file [_root-path path lines _parser-opts]
  (adapters/parse-python-file path lines))
