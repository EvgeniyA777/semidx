(ns semidx.runtime.language-registry
  (:require [clojure.string :as str]))

(def language-lanes
  [{:language "clojure"
    :extensions [".clj" ".cljc" ".cljs"]
    :provider {:provider_id "clojure-native" :provider_version "1" :classification "source"}}
   {:language "java"
    :extensions [".java"]
    :provider {:provider_id "java-native" :provider_version "1" :classification "source"}}
   {:language "elixir"
    :extensions [".ex" ".exs"]
    :provider {:provider_id "elixir-native" :provider_version "1" :classification "source"}}
   {:language "python"
    :extensions [".py"]
    :provider {:provider_id "python-native" :provider_version "1" :classification "source"}}
   {:language "typescript"
    :extensions [".ts" ".tsx"]
    :provider {:provider_id "typescript-native" :provider_version "1" :classification "source"}}
   {:language "javascript"
    :extensions [".js" ".jsx" ".mjs" ".cjs"]
    :provider {:provider_id "javascript-native" :provider_version "1" :classification "source"}}
   {:language "lua"
    :extensions [".lua"]
    :provider {:provider_id "lua-native" :provider_version "1" :classification "source"}}
   {:language "html"
    :extensions [".html" ".htm"]
    :provider {:provider_id "html-native" :provider_version "1" :classification "source"}}
   {:language "css"
    :extensions [".css"]
    :provider {:provider_id "css-native" :provider_version "1" :classification "source"}}])

(def supported-language-order
  (mapv :language language-lanes))

(defn extensions-for-language [language]
  (some (fn [{language* :language extensions :extensions}]
          (when (= language language*)
            extensions))
        language-lanes))

(def ecmascript-source-extensions
  (vec (concat (extensions-for-language "typescript")
               (extensions-for-language "javascript"))))

(def language-by-extension
  (into {}
        (mapcat (fn [{:keys [language extensions]}]
                  (map (fn [extension] [extension language]) extensions)))
        language-lanes))

(def provider-catalog
  (into {}
        (map (fn [{:keys [language provider]}] [language provider]))
        language-lanes))

(def ecmascript-test-suffixes
  [".test.ts" ".test.tsx" ".test.js" ".test.jsx" ".test.mjs" ".test.cjs"
   ".spec.ts" ".spec.tsx" ".spec.js" ".spec.jsx" ".spec.mjs" ".spec.cjs"
   "_test.ts" "_test.tsx" "_test.js" "_test.jsx" "_test.mjs" "_test.cjs"])

(defn language-by-path [path]
  (let [path* (str path)]
    (some (fn [{:keys [language extensions]}]
            (when (some #(str/ends-with? path* %) extensions)
              language))
          language-lanes)))

(defn source-path? [path]
  (boolean (language-by-path path)))

(defn provider-for-language [language]
  (get provider-catalog language))

(defn ecmascript-test-path? [path]
  (let [path* (-> path str str/lower-case (str/replace "\\" "/"))]
    (or (str/includes? path* "/test/")
        (str/starts-with? path* "test/")
        (some #(str/ends-with? path* %) ecmascript-test-suffixes))))
