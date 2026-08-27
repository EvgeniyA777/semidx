(ns semidx.runtime.launcher-cli-test
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [semidx.runtime.http :as runtime-http]
            [semidx.runtime.launcher-cli :as launcher-cli]
            [semidx.runtime.launcher-state :as launcher-state])
  (:import [java.net ServerSocket]
           [java.nio.file Files]
           [java.nio.file.attribute FileAttribute]))

(def ^:private repo-identity
  {:workspace_path "/work/repo-a"
   :repo_key "repo-a"
   :workspace_key "workspace-a"})

(def ^:private base-opts
  {:root "/work/repo-a"
   :profile "runtime-http"
   :repo_identity repo-identity
   :start_timeout_ms 1000
   :start_poll_interval_ms 1})

(defn- fake-deps
  "Injectable roles backed by atoms.

  `running` models whether a local runtime is listening on the desired endpoint."
  [{:keys [state running pid-alive?] :or {running false pid-alive? true}}]
  (let [state-atom (atom state)
        running-atom (atom running)
        starts (atom [])
        stops (atom [])
        locks (atom [])]
    {:home "/fake-launcher-home"
     :state-atom state-atom
     :running running-atom
     :starts starts
     :stops stops
     :locks locks
     :read-state (fn [_ _] @state-atom)
     :write-state! (fn [_ _ state] (reset! state-atom state) state)
     :clear-state! (fn [_ _]
                     (let [existed (some? @state-atom)]
                       (reset! state-atom nil)
                       existed))
     :with-start-lock (fn [_ _ f]
                        (let [observation (or (first @locks) :acquired)]
                          (swap! locks (fn [xs] (vec (rest xs))))
                          (f observation)))
     :state-file (fn [home _] (str home "/state.edn"))
     :log-file (fn [home _] (str home "/runtime.log"))
     :check-health (fn [_ _]
                     (if @running-atom
                       {:healthy true :status_code 200 :service "semidx-runtime-http"}
                       {:healthy false :error "connection refused"}))
     :port-open? (fn [_ _] @running-atom)
     :pid-alive? (fn [_] pid-alive?)
     :start-process! (fn [runtime opts]
                       (swap! starts conj {:runtime runtime :opts opts})
                       (reset! running-atom true)
                       {:pid 9999 :command ["clojure" "-M:runtime-http"]})
     :stop-process! (fn [pid _]
                      (swap! stops conj pid)
                      (reset! running-atom false)
                      {:stopped true :reason :terminated :forced false})
     :send-request (fn [runtime request _]
                     {:ok? true
                      :selection_id "selection-1"
                      :snapshot_id "snapshot-1"
                      :result {:echo {:host (:host runtime)
                                      :root_path (:root_path request)
                                      :query (:query request)}}})
     :now (constantly "2026-08-27T10:00:00Z")
     :sleep (fn [_] nil)}))

(def ^:private owned-state
  {:schema_version "1"
   :root_path "/work/repo-a"
   :repo_key "repo-a"
   :workspace_key "workspace-a"
   :profile "runtime-http"
   :host "127.0.0.1"
   :port 8787
   :pid 4242
   :owned true
   :started_at "2026-08-27T09:00:00Z"
   :last_health_at "2026-08-27T09:01:00Z"})

(deftest start-when-no-runtime-exists-test
  (let [deps (fake-deps {})
        result (launcher-cli/start! deps base-opts)]
    (testing "a cold slot starts exactly one runtime"
      (is (= :started (:decision result)))
      (is (= :no_state (:reason result)))
      (is (true? (:started result)))
      (is (= 1 (count @(:starts deps)))))

    (testing "the started process is recorded as launcher-owned"
      (let [state @(:state-atom deps)]
        (is (= 9999 (:pid state)))
        (is (true? (:owned state)))
        (is (= "2026-08-27T10:00:00Z" (:started_at state)))))

    (testing "the process runner is given the project root and a log file"
      (let [start (first @(:starts deps))]
        (is (= "/work/repo-a" (get-in start [:opts :working_dir])))
        (is (= "/fake-launcher-home/runtime.log" (str (get-in start [:opts :log_file]))))
        (is (= 8787 (get-in start [:runtime :port])))))))

(deftest reuse-healthy-runtime-test
  (let [deps (fake-deps {:state owned-state :running true})
        result (launcher-cli/start! deps base-opts)]
    (testing "a healthy recorded runtime is reused without starting a process"
      (is (= :reused (:decision result)))
      (is (= :healthy_runtime (:reason result)))
      (is (empty? @(:starts deps))))))

(deftest adopt-running-runtime-test
  (let [deps (fake-deps {:running true})
        result (launcher-cli/start! deps base-opts)]
    (testing "an already-listening local runtime is adopted, not duplicated"
      (is (= :reused (:decision result)))
      (is (empty? @(:starts deps))))

    (testing "adopted runtimes are recorded as not launcher-owned"
      (let [state @(:state-atom deps)]
        (is (false? (:owned state)))
        (is (nil? (:pid state)))))))

(deftest stale-state-is-cleaned-then-restarted-test
  (let [deps (fake-deps {:state owned-state :running false :pid-alive? false})
        result (launcher-cli/start! deps base-opts)]
    (testing "a dead PID with a closed port is cleaned and replaced"
      (is (= :stale-cleaned (:decision result)))
      (is (= :pid_not_alive (:reason result)))
      (is (true? (:stale_cleaned result)))
      (is (= 1 (count @(:starts deps)))))

    (testing "the replacement runtime is persisted"
      (is (= 9999 (:pid @(:state-atom deps)))))))

(deftest lock-contention-blocks-start-test
  (let [deps (fake-deps {})
        _ (reset! (:locks deps) [:contended])
        result (launcher-cli/start! deps base-opts)]
    (testing "a contended start lock blocks instead of starting a second runtime"
      (is (= :blocked (:decision result)))
      (is (= :start_lock_contended (:reason result)))
      (is (empty? @(:starts deps))))))

(deftest status-does-not-start-anything-test
  (testing "status on a cold slot reports a non-running runtime"
    (let [deps (fake-deps {})
          result (launcher-cli/status deps base-opts)]
      (is (false? (:running result)))
      (is (empty? @(:starts deps)))
      (is (nil? @(:state-atom deps)))))

  (testing "status on a healthy slot reports a reusable runtime"
    (let [deps (fake-deps {:state owned-state :running true})
          result (launcher-cli/status deps base-opts)]
      (is (true? (:running result)))
      (is (= :reused (:decision result)))
      (is (= "runtime-http" (get-in result [:runtime :profile]))))))

(deftest stop-test
  (testing "stopping a cold slot is a no-op"
    (let [deps (fake-deps {})
          result (launcher-cli/stop! deps base-opts)]
      (is (= :noop (:decision result)))
      (is (empty? @(:stops deps)))))

  (testing "stopping a launcher-owned runtime terminates it and clears state"
    (let [deps (fake-deps {:state owned-state :running true})
          result (launcher-cli/stop! deps base-opts)]
      (is (= :stopped (:decision result)))
      (is (= 4242 (:pid result)))
      (is (= [4242] @(:stops deps)))
      (is (nil? @(:state-atom deps)))))

  (testing "an adopted runtime is never killed by the launcher"
    (let [deps (fake-deps {:state (assoc owned-state :owned false :pid nil) :running true})
          result (launcher-cli/stop! deps base-opts)]
      (is (= :blocked (:decision result)))
      (is (= :not_launcher_owned (:reason result)))
      (is (empty? @(:stops deps)))
      (is (some? @(:state-atom deps))))))

(deftest request-forwards-to-reused-runtime-test
  (let [deps (fake-deps {:state owned-state :running true})
        result (launcher-cli/request! deps (assoc base-opts :query {:intent {:purpose "code_understanding"}}))]
    (testing "the request is forwarded without starting a runtime"
      (is (true? (:ok result)))
      (is (true? (:reused result)))
      (is (empty? @(:starts deps))))

    (testing "the runtime response is passed through unchanged"
      (is (= "/work/repo-a" (get-in result [:response :result :echo :root_path])))
      (is (= {:intent {:purpose "code_understanding"}}
             (get-in result [:response :result :echo :query]))))))

(deftest request-blocked-when-start-is-contended-test
  (let [deps (fake-deps {})
        _ (reset! (:locks deps) [:contended])
        result (launcher-cli/request! deps (assoc base-opts :query {}))]
    (testing "a blocked ensure short-circuits the request"
      (is (false? (:ok result)))
      (is (= :blocked (:decision result)))
      (is (nil? (:response result))))))

;; ---------------------------------------------------------------------------
;; Reuse smoke test over the real runtime HTTP edge.
;;
;; The process runner is faked so no second JVM is spawned, but state, locking,
;; health checks, and request forwarding all run for real. It proves the second
;; request reuses the first runtime instead of launching another one.
;; ---------------------------------------------------------------------------

(defn- write-file! [root rel-path content]
  (let [f (io/file root rel-path)]
    (.mkdirs (.getParentFile f))
    (spit f content)))

(defn- free-port []
  (with-open [socket (ServerSocket. 0)]
    (.getLocalPort socket)))

(defn- temp-dir [prefix]
  (str (Files/createTempDirectory prefix (make-array FileAttribute 0))))

(def ^:private smoke-query
  {:api_version "1.0"
   :schema_version "1.0"
   :intent {:purpose "code_understanding"
            :details "Locate authority implementation for process-order."}
   :targets {:symbols ["my.app.order/process-order"]
             :paths ["src/my/app/order.clj"]}
   :constraints {:token_budget 1200
                 :max_raw_code_level "enclosing_unit"
                 :freshness "current_snapshot"}
   :hints {:prefer_definitions_over_callers true}
   :options {:include_tests false
             :include_impact_hints false
             :allow_raw_code_escalation false}
   :trace {:trace_id "04111111-1111-4111-8111-111111111111"
           :request_id "launcher-smoke-001"
           :actor_id "test_runner"}})

(deftest sequential-requests-reuse-one-runtime-smoke-test
  (let [repo-root (temp-dir "sci-launcher-smoke-repo")
        launcher-home (temp-dir "sci-launcher-smoke-home")
        port (free-port)
        servers (atom [])
        starts (atom [])
        opts {:root repo-root
              :profile "runtime-http"
              :host "127.0.0.1"
              :port port
              :repo_identity {:workspace_path repo-root
                              :repo_key "smoke-repo"
                              :workspace_key "smoke-workspace"}
              :start_timeout_ms 10000
              :start_poll_interval_ms 50}
        deps (assoc (launcher-cli/default-deps)
                    :home (io/file launcher-home)
                    :start-process! (fn [runtime _]
                                      (swap! starts conj runtime)
                                      (let [server (runtime-http/start-server
                                                    {:host (:host runtime)
                                                     :port (:port runtime)})]
                                        (swap! servers conj server)
                                        {:pid (.pid (java.lang.ProcessHandle/current))
                                         :command ["fake-runtime-http"]})))]
    (write-file! repo-root "src/my/app/order.clj"
                 "(ns my.app.order)\n\n(defn process-order [ctx order]\n  (validate-order order))\n\n(defn validate-order [order]\n  (if (:id order) order (throw (ex-info \"invalid\" {}))))\n")
    (try
      (let [first-result (launcher-cli/request! deps (assoc opts :query smoke-query))
            second-result (launcher-cli/request! deps (assoc opts :query smoke-query))]
        (testing "the first request starts one runtime and succeeds"
          (is (true? (:ok first-result)) (pr-str (:response first-result)))
          (is (= :started (:decision first-result)))
          (is (= 1 (count @starts))))

        (testing "the second request reuses the running runtime"
          (is (true? (:ok second-result)))
          (is (= :reused (:decision second-result)))
          (is (true? (:reused second-result)))
          (is (= 1 (count @starts))))

        (testing "both requests return a detail payload for the same snapshot"
          (is (string? (get-in first-result [:response :result :snapshot_id])))
          (is (= (get-in first-result [:response :snapshot_id])
                 (get-in second-result [:response :snapshot_id])))
          (is (seq (get-in second-result [:response :result :raw_context]))))

        (testing "launcher state records the running runtime for this slot"
          (let [desired {:root_path repo-root
                         :repo_key "smoke-repo"
                         :workspace_key "smoke-workspace"
                         :profile "runtime-http"
                         :host "127.0.0.1"
                         :port port}
                state (launcher-state/read-state (io/file launcher-home) desired)]
            (is (= port (:port state)))
            (is (true? (:owned state))))))
      (finally
        (doseq [server @servers]
          (.stop server 0))))))

(deftest cli-request-output-is-the-runtime-payload-test
  (testing "the request payload written by the CLI is the runtime detail result"
    (let [deps (fake-deps {:state owned-state :running true})
          result (launcher-cli/request! deps (assoc base-opts :query {:a 1}))
          payload (get-in result [:response :result])]
      (is (map? payload))
      (is (string? (json/write-str payload))))))
