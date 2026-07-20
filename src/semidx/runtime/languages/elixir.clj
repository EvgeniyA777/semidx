(ns semidx.runtime.languages.elixir
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [semidx.runtime.languages.elixir.regex :as regex]
            [semidx.runtime.languages.elixir.tree-sitter :as tree-sitter]
            [semidx.runtime.languages.shared :as shared]))

(defn- tree-sitter-available? [parser-opts]
  (shared/tree-sitter-available? parser-opts))

(defn- parser-grammar-path [parser-opts]
  (shared/parser-grammar-path parser-opts :elixir))

(defn- tree-sitter-cst [abs-path grammar-path parser-opts]
  (shared/tree-sitter-cst abs-path grammar-path :elixir parser-opts))

(defn- add-tree-sitter-diag [parsed enabled? parser-opts]
  (shared/add-tree-sitter-diag parsed enabled? parser-opts))

(defn- parse-tree-sitter [root-path path src-lines parser-opts]
  (let [grammar-path (parser-grammar-path parser-opts)
        abs (-> (io/file root-path path) .getCanonicalPath)]
    (cond
      (not (tree-sitter-available? parser-opts))
      {:ok? false
       :reason {:code "tree_sitter_unavailable"
                :summary "tree-sitter CLI is unavailable for elixir tree-sitter parser."}}

      (str/blank? (str grammar-path))
      {:ok? false
       :reason {:code "tree_sitter_missing_grammar"
                :summary "No tree-sitter Elixir grammar path configured."}}

      :else
      (let [{:keys [ok? err lines]} (tree-sitter-cst abs grammar-path parser-opts)]
        (if-not ok?
          {:ok? false
           :reason {:code "tree_sitter_parse_failed"
                    :summary (str "tree-sitter parse failed: " (subs (str err) 0 (min 220 (count (str err)))))}}
          (tree-sitter/parse-file path src-lines lines))))))

(defn parse-file [root-path path lines {:keys [elixir_engine tree_sitter_enabled]
                                        :or {elixir_engine :regex}
                                        :as parser-opts}]
  (let [engine (if (true? tree_sitter_enabled) :tree-sitter elixir_engine)
        parsed (if (= engine :tree-sitter)
                 (let [{:keys [ok? result reason]} (parse-tree-sitter root-path path lines parser-opts)]
                   (if ok?
                     result
                     (-> (regex/parse-file path lines)
                         (update :diagnostics conj reason))))
                 (regex/parse-file path lines))]
    (add-tree-sitter-diag parsed (or tree_sitter_enabled (= engine :tree-sitter)) parser-opts)))
