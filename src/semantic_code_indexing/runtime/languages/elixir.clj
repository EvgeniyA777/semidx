(ns semantic-code-indexing.runtime.languages.elixir
  (:require [clojure.java.io :as io]
            [clojure.java.shell :as sh]
            [clojure.string :as str]
            [semantic-code-indexing.runtime.languages.elixir.regex :as regex]
            [semantic-code-indexing.runtime.languages.elixir.tree-sitter :as tree-sitter]))

(defonce ^:private tree-sitter-availability (atom nil))

(defn- tree-sitter-available? []
  (if (some? @tree-sitter-availability)
    @tree-sitter-availability
    (let [{:keys [exit]} (try
                           (sh/sh "tree-sitter" "--version")
                           (catch Exception _ {:exit 127}))
          available? (zero? (int exit))]
      (reset! tree-sitter-availability available?)
      available?)))

(defn- parser-grammar-path [parser-opts]
  (or (get-in parser-opts [:tree_sitter_grammars :elixir])
      (get-in parser-opts [:tree_sitter_grammars "elixir"])
      (get parser-opts :tree_sitter_elixir_grammar)
      (System/getenv "SCI_TREE_SITTER_ELIXIR_GRAMMAR_PATH")))

(def ^:private ts-line-re
  #"^\s*(\d+):(\d+)\s*-\s*(\d+):(\d+)(\s+)(.+?)\s*$")

(def ^:private ansi-escape-re
  #"\u001B\[[0-9;]*m")

(defonce ^:private tree-sitter-config-cache (atom {}))

(defn- parse-ts-line [line]
  (let [clean-line (str/replace (str line) ansi-escape-re "")]
    (when-let [[_ sr sc er ec spacing text] (re-find ts-line-re clean-line)]
    (let [plain (str/trim (first (str/split text #"`")))
          source (if (str/includes? plain ":")
                   (second (str/split plain #":\s*" 2))
                   plain)
          node-type (last (str/split (str/trim source) #"\s+"))
          value (some-> (re-find #"`([^`]*)`" text) second)]
      {:indent (count spacing)
       :start-row (parse-long sr)
       :start-col (parse-long sc)
       :end-row (parse-long er)
       :end-col (parse-long ec)
       :text text
       :node-type node-type
       :value value}))))

(defn- tree-sitter-config-path [grammar-path]
  (let [parser-dir (some-> grammar-path io/file .getCanonicalFile .getParent)
        escaped-dir (-> (str parser-dir)
                        (str/replace "\\" "\\\\")
                        (str/replace "\"" "\\\""))]
    (or (get @tree-sitter-config-cache parser-dir)
        (let [config-file (io/file (System/getProperty "java.io.tmpdir")
                                   (format "sci-tree-sitter-elixir-%s.json" (Math/abs (hash (str parser-dir)))))]
          (spit config-file (format "{\"parser-directories\":[\"%s\"]}" escaped-dir))
          (swap! tree-sitter-config-cache assoc parser-dir (.getPath config-file))
          (.getPath config-file)))))

(defn- tree-sitter-cst [abs-path grammar-path]
  (let [config-path (tree-sitter-config-path grammar-path)
        tmpdir (System/getProperty "java.io.tmpdir")
        {:keys [exit out err]}
        (try
          (sh/sh "tree-sitter" "parse" "--cst" "--config-path" config-path "--grammar-path" grammar-path abs-path
                 :env (cond-> {"XDG_CACHE_HOME" (or (System/getenv "XDG_CACHE_HOME")
                                                   tmpdir)
                               "TMPDIR" tmpdir}
                        (System/getenv "HOME") (assoc "HOME" (System/getenv "HOME"))))
          (catch Exception e
            {:exit 127 :out "" :err (.getMessage e)}))]
    (if (zero? (int exit))
      {:ok? true
       :lines (->> (str/split-lines out) (keep parse-ts-line) vec)
       :err nil}
      {:ok? false
       :lines []
       :err (or err "tree-sitter parse failed")})))

(defn- add-tree-sitter-diag [parsed enabled?]
  (if enabled?
    (if (tree-sitter-available?)
      (update parsed :diagnostics conj {:code "tree_sitter_probe"
                                        :summary "tree-sitter CLI detected."})
      (update parsed :diagnostics conj {:code "tree_sitter_unavailable"
                                        :summary "tree-sitter requested but CLI is unavailable; using adapter parser."}))
    parsed))

(defn- parse-tree-sitter [root-path path src-lines parser-opts]
  (let [grammar-path (parser-grammar-path parser-opts)
        abs (-> (io/file root-path path) .getCanonicalPath)]
    (cond
      (not (tree-sitter-available?))
      {:ok? false
       :reason {:code "tree_sitter_unavailable"
                :summary "tree-sitter CLI is unavailable for elixir tree-sitter parser."}}

      (str/blank? (str grammar-path))
      {:ok? false
       :reason {:code "tree_sitter_missing_grammar"
                :summary "No tree-sitter Elixir grammar path configured."}}

      :else
      (let [{:keys [ok? err lines]} (tree-sitter-cst abs grammar-path)]
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
    (add-tree-sitter-diag parsed (or tree_sitter_enabled (= engine :tree-sitter)))))
