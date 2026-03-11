(ns semantic-code-indexing.runtime.project-context
  (:require [semantic-code-indexing.runtime.language-activation :as activation]))

(def ^:private default-retry-after-seconds 2)
(def ^:private default-activation-timeout-seconds 120)

(defn- now-iso []
  (str (java.time.Instant/now)))

(defn- parse-instant [value]
  (when (seq value)
    (try
      (java.time.Instant/parse (str value))
      (catch Exception _ nil))))

(defn- activation-expired? [entry]
  (let [timeout-seconds (long (or (:activation_timeout_seconds entry)
                                  default-activation-timeout-seconds))
        started-at (parse-instant (:activation_started_at entry))]
    (boolean (and started-at
                  (> (.getSeconds (java.time.Duration/between started-at (java.time.Instant/now)))
                     timeout-seconds)))))

(defn project-scope
  ([root-path]
   (project-scope root-path nil))
  ([root-path tenant-id]
   (let [canonical-root (activation/canonical-root-path root-path)]
     {:registry_key (if (seq tenant-id)
                      [tenant-id canonical-root]
                      canonical-root)
      :root_path canonical-root
      :tenant_id tenant-id})))

(defn project-registry []
  (atom {}))

(defn merge-language-policy [server-policy request-policy]
  (activation/merge-language-policies server-policy request-policy))

(defn project-entry [registry {:keys [registry_key]}]
  (get @registry registry_key))

(defn- activation-in-progress! [{:keys [root_path tenant_id]} entry]
  (throw (ex-info "language activation is already in progress for this project"
                  {:type :language_activation_in_progress
                   :message "language activation is already in progress for this project"
                   :details {:root_path (or (:root_path entry) root_path)
                             :tenant_id (or (:tenant_id entry) tenant_id)
                             :activation_state "activation_in_progress"
                             :activation_started_at (:activation_started_at entry)
                             :retry_after_seconds (or (:retry_after_seconds entry)
                                                      default-retry-after-seconds)
                             :recommended_action "retry_same_request"
                             :active_languages (:active_languages entry)
                             :detected_languages (:detected_languages entry)}})))

(defn refresh-project-index!
  [registry {:keys [registry_key root_path tenant_id] :as scope} build-fn]
  (let [claimed? (atom false)]
    (swap! registry
           (fn [state]
             (let [entry (get state registry_key)]
               (cond
                 (and (= "activation_in_progress" (:activation_state entry))
                      (not (activation-expired? entry)))
                 (do
                   (reset! claimed? false)
                   state)

                 :else
                 (do
                   (reset! claimed? true)
                   (assoc state registry_key
                          (merge entry
                                 {:root_path root_path
                                  :tenant_id tenant_id
                                  :activation_state "activation_in_progress"
                                  :activation_started_at (now-iso)
                                  :activation_owner_id (str (java.util.UUID/randomUUID))
                                  :retry_after_seconds default-retry-after-seconds
                                  :activation_timeout_seconds default-activation-timeout-seconds})))))))
    (when-not @claimed?
      (activation-in-progress! scope (project-entry registry scope)))
    (try
      (let [index (build-fn)
            entry {:root_path root_path
                   :tenant_id tenant_id
                   :index index
                   :snapshot_id (:snapshot_id index)
                   :detected_languages (:detected_languages index)
                   :active_languages (:active_languages index)
                   :supported_languages (:supported_languages index)
                   :language_fingerprint (:language_fingerprint index)
                   :activation_state (:activation_state index)
                   :selection_hint (:selection_hint index)
                    :manual_language_selection (:manual_language_selection index)}]
        (swap! registry assoc registry_key entry)
        entry)
      (catch Exception e
        (swap! registry update registry_key #(when % (assoc % :activation_state "refresh_required")))
        (throw e)))))

(defn ensure-project-index!
  [registry scope request build-fn]
  (if-let [entry (project-entry registry scope)]
    (let [entry* (if (= "activation_in_progress" (:activation_state entry))
                   (if (activation-expired? entry)
                     (refresh-project-index! registry scope build-fn)
                     (activation-in-progress! scope entry))
                   entry)]
      (activation/ensure-request-languages-active! entry* request)
      entry*)
    (refresh-project-index! registry scope build-fn)))
