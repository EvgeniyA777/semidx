(ns semantic-code-indexing.contracts.cli
  (:gen-class)
  (:require [semantic-code-indexing.contracts.validator :as validator]))

(defn -main [& _args]
  (let [{:keys [checked failures]} (validator/validate-contracts)]
    (println (str "checked_json_files=" checked))
    (if (empty? failures)
      (do
        (println "contracts_validation=ok")
        (System/exit 0))
      (do
        (println (str "contracts_validation=failed count=" (count failures)))
        (doseq [{:keys [path errors]} failures]
          (println (str "file=" path))
          (doseq [e errors]
            (println (str "  error=" e))))
        (System/exit 1)))))
