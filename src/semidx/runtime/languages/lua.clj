(ns semidx.runtime.languages.lua
  (:require [semidx.runtime.adapters :as adapters]))

(defn parse-file [_root-path path lines _parser-opts]
  (adapters/parse-lua-file path lines))
