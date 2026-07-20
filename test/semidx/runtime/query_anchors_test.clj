(ns semidx.runtime.query-anchors-test
  (:require [clojure.test :refer [deftest is testing]]
            [semidx.runtime.query-anchors :as qa]))

(defn- intent-query [details]
  {:intent {:purpose "edit_preparation" :details details}})

(deftest state-intent-fires-on-lifecycle-work-test
  (testing "the observed disconnect/reconnect case fires with its terms"
    (let [q (intent-query "Add Google Sheets disconnect and reconnect-required handling")]
      (is (true? (qa/state-intent? q)))
      (is (= ["disconnect" "reconnect"] (qa/matched-state-terms q)))))

  (testing "credential/secret/token language fires"
    (let [q (intent-query "token refresh clears the secret too early")]
      (is (true? (qa/state-intent? q)))
      (is (= #{"token" "secret"} (set (qa/matched-state-terms q))))))

  (testing "persistence/entity/lifecycle/timestamp language fires with all terms"
    (let [q (intent-query "persist the entity lifecycle timestamp")]
      (is (true? (qa/state-intent? q)))
      (is (= #{"persist" "entity" "lifecycle" "timestamp"}
             (set (qa/matched-state-terms q)))))))

(deftest state-intent-tokenizes-camelcase-and-snakecase-test
  (testing "camelCase method names split into matchable tokens"
    (let [q (intent-query "how does updateStatus work")]
      (is (true? (qa/state-intent? q)))
      (is (= ["status"] (qa/matched-state-terms q)))))

  (testing "camelCase field names like connectedAt match the connect stem"
    (let [q (intent-query "does saveOAuthConnection preserve connectedAt")]
      (is (true? (qa/state-intent? q)))
      (is (contains? (set (qa/matched-state-terms q)) "connected")))))

(deftest state-intent-reads-target-symbols-test
  (testing "explicit target symbols are a valid trigger source"
    (let [q {:intent {:purpose "edit_preparation" :details "fix this"}
             :targets {:symbols ["GoogleSheetsConnection/connectedAt"]}}]
      (is (true? (qa/state-intent? q)))
      (is (seq (qa/matched-state-terms q))))))

(deftest state-intent-stays-quiet-on-unrelated-work-test
  (testing "unrelated intent does not fire"
    (let [q (intent-query "render the invoice PDF export")]
      (is (false? (qa/state-intent? q)))
      (is (empty? (qa/matched-state-terms q)))))

  (testing "no false positive from words that merely contain a trigger substring"
    (let [q (intent-query "the statement parser handles static files")]
      (is (false? (qa/state-intent? q)))
      (is (empty? (qa/matched-state-terms q))))))

(deftest matched-state-terms-are-distinct-test
  (testing "repeated triggers collapse to distinct terms"
    (let [q (intent-query "status change updates status and status history")]
      (is (= ["status"] (qa/matched-state-terms q))))))

(deftest state-intent-handles-empty-and-nil-safely-test
  (testing "missing intent details and absent targets never throw and never fire"
    (is (false? (qa/state-intent? {})))
    (is (false? (qa/state-intent? {:intent {:purpose "code_understanding"}})))
    (is (empty? (qa/matched-state-terms {})))))
