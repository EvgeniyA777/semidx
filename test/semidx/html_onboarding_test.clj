(ns semidx.html-onboarding-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [semidx.core :as sci]))

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(defn- tmp-root [prefix]
  (str (java.nio.file.Files/createTempDirectory
        prefix (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- units-for-path [index path]
  (->> (:unit_order index)
       (map #(get (:units index) %))
       (filter #(= path (:path %)))
       vec))

(defn- provider-for [index path]
  (some->> (get-in index [:workspace_state :files])
           (filter #(= path (:path %)))
           first
           :provider_id))

(deftest html-adapter-onboarding-regression-test
  (let [root (tmp-root "sci-html-onboarding")
        _ (write-file! root "public/index.html"
                       "<!doctype html>\n<html>\n<head>\n  <link rel=\"stylesheet\" href=\"styles.css\">\n  <script src=\"app.js\"></script>\n</head>\n<body>\n  <main id=\"hero\" class=\"landing shell\">\n    <button class=\"cta-button primary\" data-action=\"checkout\">Buy</button>\n    <img src=\"assets/logo.png\" alt=\"Logo\">\n  </main>\n</body>\n</html>\n")
        _ (write-file! root "public/styles.css"
                       ".cta-button { color: var(--brand-color); }\n#hero { padding: 2rem; }\n")
        storage (sci/in-memory-storage)
        index (sci/create-index {:root_path root :storage storage})
        html-units (units-for-path index "public/index.html")
        css-selector-id (some->> (vals (:units index))
                                 (filter #(= ".cta-button" (:symbol %)))
                                 first
                                 :unit_id)
        css-callers (sci/query-callers storage root css-selector-id {:limit 20})]
    (testing "HTML is detected, activated, and provider-tagged"
      (is (= "html" (get-in index [:files "public/index.html" :language])))
      (is (= "full" (get-in index [:files "public/index.html" :parser_mode])))
      (is (some #{"html"} (:detected_languages index)))
      (is (some #{"html"} (:active_languages index)))
      (is (= "html-native" (provider-for index "public/index.html"))))
    (testing "HTML parser extracts document and element units"
      (is (some #(= "public/document" (:symbol %)) html-units))
      (is (some #(some #{"#hero"} (:calls %)) html-units))
      (is (some #(some #{".cta-button"} (:calls %)) html-units)))
    (testing "HTML usage calls CSS selector units through selector tokens"
      (is css-selector-id)
      (is (some #(= "public/index.html" (:path %)) css-callers)))))

(deftest html-css-language-policy-regression-test
  (let [root (tmp-root "sci-html-policy")
        _ (write-file! root "src/app.clj" "(ns app)\n(defn run [] :ok)\n")
        _ (write-file! root "public/index.html" "<main class=\"cta-button\"></main>\n")
        _ (write-file! root "public/styles.css" ".cta-button { color: red; }\n")
        storage (sci/in-memory-storage)
        policy {:allow_languages ["clojure"]}
        index (sci/create-index {:root_path root
                                 :storage storage
                                 :load_latest true
                                 :language_policy policy})]
    (testing "full builds exclude HTML/CSS when policy allows only Clojure"
      (is (= ["clojure"] (:active_languages index)))
      (is (contains? (:files index) "src/app.clj"))
      (is (not (contains? (:files index) "public/index.html")))
      (is (not (contains? (:files index) "public/styles.css"))))
    (testing "incremental freshness does not pull newly added web files into a Clojure-only index"
      (write-file! root "public/later.html" "<button class=\"later\"></button>\n")
      (let [after (sci/create-index {:root_path root
                                     :storage storage
                                     :load_latest true
                                     :language_policy policy})]
        (is (= ["clojure"] (:active_languages after)))
        (is (not (contains? (:files after) "public/later.html")))))))
