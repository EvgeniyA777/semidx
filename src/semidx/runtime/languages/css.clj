(ns semidx.runtime.languages.css
  (:require [clojure.string :as str]
            [semidx.runtime.languages.shared :as shared]))

(def ^:private import-re #"@import\s+(?:url\(\s*)?[\"']?([^\"'\)\s;]+)")
(def ^:private url-re #"url\(\s*[\"']?([^\"'\)]+)")
(def ^:private custom-property-re #"(--[A-Za-z_][A-Za-z0-9_-]*)\s*:")
(def ^:private selector-token-re #"([.#][A-Za-z_][A-Za-z0-9_-]*)")
(def ^:private at-rule-re #"@([A-Za-z-]+)\s+([^\{;]+)")
(def ^:private tag-selector-re #"(?i)^\s*([a-z][a-z0-9-]*)")

(defn- trim-signature [line]
  (shared/trim-signature line))

(defn- strip-ext [path]
  (str/replace (str path) #"\.css$" ""))

(defn- module-name [path]
  (let [base (-> path
                 str
                 (str/replace "\\" "/")
                 strip-ext
                 (str/replace #"^\./+" "")
                 (str/replace #"^/+" "")
                 (str/replace #"/" ".")
                 (str/replace #"^\.+|\.+$" ""))]
    (if (str/blank? base) "styles" base)))

(defn- normalize-ref [value]
  (let [v (-> (str value)
              str/trim
              (str/replace "\\" "/")
              (str/replace #"[?#].*$" ""))]
    (when-not (str/blank? v) v)))

(defn- refs-in-line [line]
  (->> (concat (map second (re-seq import-re line))
               (map second (re-seq url-re line)))
       (keep normalize-ref)
       distinct
       vec))

(defn- selector-head [line]
  (let [head (first (str/split (str line) #"\{" 2))
        trimmed (str/trim head)]
    (when (and (str/includes? (str line) "{")
               (not (str/blank? trimmed)))
      trimmed)))

(defn- selector-tokens [selector]
  (let [class-and-id (map second (re-seq selector-token-re selector))
        tag (when-not (str/starts-with? (str/trim selector) "@")
              (some-> (re-find tag-selector-re selector) second str/lower-case))]
    (->> (concat class-and-id [tag])
         (remove str/blank?)
         distinct
         vec)))

(defn- rule-end-line [lines start-idx]
  (loop [idx start-idx
         depth 0
         opened? false]
    (if (>= idx (count lines))
      (count lines)
      (let [line (nth lines idx)
            opens (count (re-seq #"\{" line))
            closes (count (re-seq #"\}" line))
            depth* (+ depth opens (- closes))
            opened?* (or opened? (pos? opens))]
        (if (and opened?* (<= depth* 0))
          (inc idx)
          (recur (inc idx) depth* opened?*))))))

(defn- selector-units [path module lines]
  (->> lines
       (map-indexed vector)
       (mapcat
        (fn [[idx line]]
          (let [line-number (inc idx)]
            (when-let [selector (selector-head line)]
              (->> (selector-tokens selector)
                   (map-indexed
                    (fn [ordinal token]
                      {:unit_id (str path "::css-selector::" line-number "::" ordinal "::" token)
                       :path path
                       :module module
                       :symbol token
                       :kind "selector"
                       :start_line line-number
                       :end_line (rule-end-line lines idx)
                       :signature (trim-signature line)
                       :summary (str "CSS selector " token)
                       :imports (refs-in-line line)
                       :calls []
                       :call_tokens (refs-in-line line)})))))))
       (remove nil?)
       vec))

(defn- at-rule-units [path module lines]
  (->> lines
       (map-indexed vector)
       (keep
        (fn [[idx line]]
          (when-let [[_ rule body] (re-find at-rule-re line)]
            (let [line-number (inc idx)
                  rule* (str/lower-case rule)
                  symbol (if (= "keyframes" rule*)
                           (str "@keyframes " (str/trim body))
                           (str "@" rule*))]
              {:unit_id (str path "::css-at-rule::" line-number "::" rule*)
               :path path
               :module module
               :symbol symbol
               :kind "at-rule"
               :start_line line-number
               :end_line (rule-end-line lines idx)
               :signature (trim-signature line)
               :summary (str "CSS " symbol " rule")
               :imports (refs-in-line line)
               :calls []
               :call_tokens (refs-in-line line)}))))
       vec))

(defn- custom-property-units [path module lines]
  (->> lines
       (map-indexed vector)
       (mapcat
        (fn [[idx line]]
          (let [line-number (inc idx)]
            (->> (re-seq custom-property-re line)
                 (map-indexed
                  (fn [ordinal [_ prop]]
                    {:unit_id (str path "::css-var::" line-number "::" ordinal "::" prop)
                     :path path
                     :module module
                     :symbol prop
                     :kind "variable"
                     :start_line line-number
                     :end_line line-number
                     :signature (trim-signature line)
                     :summary (str "CSS custom property " prop)
                     :imports []
                     :calls []
                     :call_tokens []}))))))
       vec))

(defn- stylesheet-unit [path module lines imports units]
  {:unit_id (str path "::css-stylesheet")
   :path path
   :module module
   :symbol (str module "/stylesheet")
   :kind "stylesheet"
   :start_line 1
   :end_line (max 1 (count lines))
   :signature (if (seq lines) (trim-signature (first lines)) "")
   :summary (str "CSS stylesheet " path)
   :imports imports
   :calls []
   :call_tokens (->> units (mapcat :call_tokens) distinct vec)})

(defn parse-file [_root-path path lines _parser-opts]
  (let [module (module-name path)
        selector-units* (selector-units path module lines)
        at-rules (at-rule-units path module lines)
        vars (custom-property-units path module lines)
        imports (->> lines (mapcat refs-in-line) distinct vec)
        units (vec (concat selector-units* at-rules vars))
        stylesheet (stylesheet-unit path module lines imports units)]
    {:module module
     :imports imports
     :units (vec (cons stylesheet units))
     :diagnostics []
     :parser_mode "full"}))
