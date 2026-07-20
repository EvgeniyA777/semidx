(ns semidx.runtime.languages.shared
  (:require [clojure.java.io :as io]
            [clojure.java.shell :as sh]
            [clojure.string :as str]))

(def ^:private tree-sitter-line-re
  #"^\s*(\d+):(\d+)\s*-\s*(\d+):(\d+)(\s+)(.+?)\s*$")

(def ^:private ansi-escape-re
  #"\u001B\[[0-9;]*m")

(def ^:private tree-sitter-diagnostic-languages
  #{"clojure" "elixir" "java" "typescript" "javascript"})

(defonce ^:private tree-sitter-availability (atom nil))
(defonce ^:private tree-sitter-config-cache (atom {}))

(defn slurp-lines [file]
  (-> file slurp str/split-lines vec))

(defn trim-signature [line]
  (let [t (str/trim (or line ""))]
    (subs t 0 (min 180 (count t)))))

(defn safe-line [lines n]
  (let [idx (dec (max 1 n))]
    (if (< idx (count lines))
      (trim-signature (nth lines idx))
      "")))

(defn unit-end-lines [starts total-lines]
  (let [pairs (partition 2 1 (concat starts [(inc total-lines)]))]
    (mapv (fn [[s n]] (max s (dec n))) pairs)))

(defn tail-token [token]
  (some-> token str (str/split #"[\./#]") last))

(defn tree-sitter-available? []
  (if (some? @tree-sitter-availability)
    @tree-sitter-availability
    (let [{:keys [exit]} (try
                           (sh/sh "tree-sitter" "--version")
                           (catch Exception _ {:exit 127}))
          available? (zero? (int exit))]
      (reset! tree-sitter-availability available?)
      available?)))

(defn parser-grammar-path [parser-opts lang]
  (or (get-in parser-opts [:tree_sitter_grammars lang])
      (get-in parser-opts [:tree_sitter_grammars (keyword lang)])
      (get parser-opts (keyword (str "tree_sitter_" (name lang) "_grammar")))
      (System/getenv (case lang
                       :clojure "SEMIDX_TREE_SITTER_CLOJURE_GRAMMAR_PATH"
                       :elixir "SEMIDX_TREE_SITTER_ELIXIR_GRAMMAR_PATH"
                       :java "SEMIDX_TREE_SITTER_JAVA_GRAMMAR_PATH"
                       :typescript "SEMIDX_TREE_SITTER_TYPESCRIPT_GRAMMAR_PATH"
                       :javascript "SEMIDX_TREE_SITTER_JAVASCRIPT_GRAMMAR_PATH"
                       nil))))

(defn parse-tree-sitter-line [line]
  (let [clean-line (str/replace (str line) ansi-escape-re "")]
    (when-let [[_ sr sc er ec spacing text] (re-find tree-sitter-line-re clean-line)]
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

(defn tree-sitter-config-path
  ([grammar-path]
   (tree-sitter-config-path grammar-path nil))
  ([grammar-path config-name]
   (let [parser-dir (some-> grammar-path io/file .getCanonicalFile .getParent)
         escaped-dir (-> (str parser-dir)
                         (str/replace "\\" "\\\\")
                         (str/replace "\"" "\\\""))
         cache-key [config-name parser-dir]
         parser-dir-hash (Math/abs (hash (str parser-dir)))
         file-name (if config-name
                     (format "sci-tree-sitter-%s-%s.json" (name config-name) parser-dir-hash)
                     (format "sci-tree-sitter-%s.json" parser-dir-hash))]
     (or (get @tree-sitter-config-cache cache-key)
         (let [config-file (io/file (System/getProperty "java.io.tmpdir") file-name)]
           (spit config-file (format "{\"parser-directories\":[\"%s\"]}" escaped-dir))
           (swap! tree-sitter-config-cache assoc cache-key (.getPath config-file))
           (.getPath config-file))))))

(defn tree-sitter-cst
  ([abs-path grammar-path]
   (tree-sitter-cst abs-path grammar-path nil))
  ([abs-path grammar-path config-name]
   (let [config-path (tree-sitter-config-path grammar-path config-name)
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
        :lines (->> (str/split-lines out) (keep parse-tree-sitter-line) vec)
        :err nil}
       {:ok? false
        :lines []
        :err (or err "tree-sitter parse failed")}))))

(defn add-tree-sitter-diag
  ([parsed enabled?]
   (if enabled?
     (if (tree-sitter-available?)
       (update parsed :diagnostics conj {:code "tree_sitter_probe"
                                         :summary "tree-sitter CLI detected."})
       (update parsed :diagnostics conj {:code "tree_sitter_unavailable"
                                         :summary "tree-sitter requested but CLI is unavailable; using adapter parser."}))
     parsed))
  ([parsed enabled? language]
   (if (and enabled? (tree-sitter-diagnostic-languages (str language)))
     (add-tree-sitter-diag parsed true)
     parsed)))
