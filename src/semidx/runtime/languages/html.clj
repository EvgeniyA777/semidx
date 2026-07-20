(ns semidx.runtime.languages.html
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [semidx.runtime.languages.shared :as shared]))

(def ^:private tag-re #"<\s*([A-Za-z][A-Za-z0-9:_-]*)([^<>]*?)(?:/?)>")
(def ^:private attr-re #"([A-Za-z_:][A-Za-z0-9_:.-]*)(?:\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+)))?")
(def ^:private reference-attrs #{"href" "src" "action" "poster" "data-src"})

(defn- trim-signature [line]
  (shared/trim-signature line))

(defn- strip-ext [path]
  (-> (str path)
      (str/replace #"\.(html|htm)$" "")
      (str/replace #"/index$" "")))

(defn- module-name [path]
  (let [base (-> path
                 str
                 (str/replace "\\" "/")
                 strip-ext
                 (str/replace #"^\./+" "")
                 (str/replace #"^/+" "")
                 (str/replace #"/" ".")
                 (str/replace #"^\.+|\.+$" ""))]
    (if (str/blank? base) "index" base)))

(defn- normalize-ref [value]
  (let [v (-> (str value)
              str/trim
              (str/replace "\\" "/")
              (str/replace #"[?#].*$" ""))]
    (when-not (or (str/blank? v)
                  (str/starts-with? v "#")
                  (str/starts-with? v "mailto:")
                  (str/starts-with? v "tel:")
                  (str/starts-with? v "javascript:"))
      v)))

(defn- parse-attrs [text]
  (reduce
   (fn [acc [_ k v1 v2 v3]]
     (assoc acc (str/lower-case k) (or v1 v2 v3 "")))
   {}
   (re-seq attr-re (or text ""))))

(defn- class-tokens [attrs]
  (->> (str/split (or (get attrs "class") "") #"\s+")
       (map str/trim)
       (remove str/blank?)
       distinct
       (mapv #(str "." %))))

(defn- id-token [attrs]
  (when-let [id (not-empty (str/trim (or (get attrs "id") "")))]
    (str "#" id)))

(defn- ref-tokens [attrs]
  (->> reference-attrs
       (keep #(normalize-ref (get attrs %)))
       distinct
       vec))

(defn- interesting-tag? [tag attrs]
  (or (contains? #{"a" "button" "form" "input" "link" "script" "img" "style" "section" "main" "nav"} tag)
      (seq (get attrs "id"))
      (seq (get attrs "class"))))

(defn- element-symbol [module tag attrs line-number ordinal]
  (str module "/" tag "-" line-number "-" ordinal))

(defn- tag-units [path module lines]
  (->> lines
       (map-indexed vector)
       (mapcat
        (fn [[idx line]]
          (let [line-number (inc idx)]
            (->> (re-seq tag-re line)
                 (map-indexed
                  (fn [ordinal [_ raw-tag raw-attrs]]
                    (let [tag (str/lower-case raw-tag)
                          attrs (parse-attrs raw-attrs)
                          selectors (cond-> (class-tokens attrs)
                                      (id-token attrs) (conj (id-token attrs)))
                          refs (ref-tokens attrs)
                          call-tokens (vec (distinct (concat selectors refs)))]
                      (when (interesting-tag? tag attrs)
                        {:unit_id (str path "::html-element::" line-number "::" ordinal)
                         :path path
                         :module module
                         :symbol (element-symbol module tag attrs line-number ordinal)
                         :kind "element"
                         :start_line line-number
                         :end_line line-number
                         :signature (trim-signature line)
                         :summary (str "HTML <" tag "> element")
                         :imports refs
                         :calls call-tokens
                         :call_tokens []}))))))))
       (remove nil?)
       vec))

(defn- document-unit [path module lines element-units]
  (let [tokens (->> element-units (mapcat :calls) distinct vec)
        imports (->> element-units (mapcat :imports) distinct vec)]
    {:unit_id (str path "::html-document")
     :path path
     :module module
     :symbol (str module "/document")
     :kind "document"
     :start_line 1
     :end_line (max 1 (count lines))
     :signature (if (seq lines) (trim-signature (first lines)) "")
     :summary (str "HTML document " path)
     :imports imports
     :calls tokens
     :call_tokens []}))

(defn parse-file [_root-path path lines _parser-opts]
  (let [module (module-name path)
        elements (tag-units path module lines)
        document (document-unit path module lines elements)]
    {:module module
     :imports (:imports document)
     :units (vec (cons document elements))
     :diagnostics []
     :parser_mode "full"}))
