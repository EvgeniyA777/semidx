(ns semantic-code-indexing.runtime.languages.elixir
  (:require [semantic-code-indexing.runtime.adapters :as adapters]))

(defn parse-file [root-path path lines parser-opts]
  (adapters/parse-elixir-file root-path path lines parser-opts))
