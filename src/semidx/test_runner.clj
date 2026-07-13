(ns semidx.test-runner
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :as t]
            [clojure.tools.namespace.find :as ns-find]))

(defn discover-test-namespaces
  "Discover every `*-test` namespace under the `test` directory so new tests need
  no manual registration. Sorted for a deterministic default order."
  []
  (->> (ns-find/find-namespaces-in-dir (io/file "test"))
       (filter #(str/ends-with? (name %) "-test"))
       distinct
       sort
       vec))

(defn run [namespaces]
  (run! require namespaces)
  (apply t/run-tests namespaces))

(defn -main [& _]
  (let [namespaces (discover-test-namespaces)]
    (println "Discovered" (count namespaces) "test namespaces")
    (let [result (run namespaces)
          failures (+ (:fail result) (:error result))]
      (System/exit (if (zero? failures) 0 1)))))
