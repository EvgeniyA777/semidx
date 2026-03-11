(ns semantic-code-indexing.mcp.session-registry
  (:require [semantic-code-indexing.mcp.core :as core])
  (:import [java.util UUID]
           [java.util.concurrent LinkedBlockingQueue TimeUnit]))

(def default-session-ttl-ms (* 30 60 1000))
(def default-sse-poll-timeout-ms 1000)
(def close-sentinel ::close)

(defn now-ms []
  (System/currentTimeMillis))

(defn queue []
  (LinkedBlockingQueue.))

(defn new-registry
  ([] (new-registry {}))
  ([{:keys [ttl-ms]
     :or {ttl-ms default-session-ttl-ms}}]
   (atom {:ttl-ms ttl-ms
          :sessions {}})))

(defn- expired-entry? [ttl-ms now entry]
  (> (- now (:last_seen_at entry 0)) ttl-ms))

(defn- close-sse! [entry]
  (when-let [q (get-in entry [:sse :queue])]
    (.offer ^LinkedBlockingQueue q close-sentinel))
  (when-let [close-fn (get-in entry [:sse :close_fn])]
    (future
      (try
        (close-fn)
        (catch Exception _ nil)))))

(defn cleanup-expired-sessions! [registry]
  (let [now (now-ms)]
    (swap! registry
           (fn [current]
             (let [ttl-ms (:ttl-ms current)
                   expired (->> (:sessions current)
                                (filter (fn [[_ entry]]
                                          (expired-entry? ttl-ms now entry)))
                                (map second)
                                vec)]
               (doseq [entry expired]
                 (close-sse! entry))
               (update current :sessions
                       (fn [sessions]
                         (reduce-kv (fn [acc session-id entry]
                                      (if (expired-entry? ttl-ms now entry)
                                        acc
                                        (assoc acc session-id entry)))
                                    {}
                                    sessions))))))))

(defn create-session! [registry session-config]
  (cleanup-expired-sessions! registry)
  (let [session-id (str (UUID/randomUUID))
        now (now-ms)
        state (core/new-session-state (assoc session-config :session-id session-id))
        entry {:session_id session-id
               :created_at now
               :last_seen_at now
               :state state}]
    (swap! registry assoc-in [:sessions session-id] entry)
    entry))

(defn touch-session! [registry session-id]
  (cleanup-expired-sessions! registry)
  (let [now (now-ms)]
    (when-let [entry (get-in @registry [:sessions session-id])]
      (swap! registry assoc-in [:sessions session-id :last_seen_at] now)
      (assoc entry :last_seen_at now))))

(defn session-entry [registry session-id]
  (touch-session! registry session-id))

(defn session-state [registry session-id]
  (:state (session-entry registry session-id)))

(defn attach-sse! [registry session-id close-fn]
  (cleanup-expired-sessions! registry)
  (let [connection-id (str (UUID/randomUUID))
        q (queue)
        result (atom nil)]
    (swap! registry
           (fn [current]
             (if-let [entry (get-in current [:sessions session-id])]
               (do
                 (when-let [old-entry (get-in current [:sessions session-id])]
                   (close-sse! old-entry))
                 (reset! result {:session_id session-id
                                 :connection_id connection-id
                                 :queue q
                                 :state (:state entry)})
                 (assoc-in current [:sessions session-id]
                           (assoc entry
                                  :last_seen_at (now-ms)
                                  :sse {:connection_id connection-id
                                        :queue q
                                        :close_fn close-fn})))
               current)))
    @result))

(defn detach-sse! [registry session-id connection-id]
  (swap! registry
         (fn [current]
           (if (= connection-id (get-in current [:sessions session-id :sse :connection_id]))
             (update-in current [:sessions session-id] dissoc :sse)
             current))))

(defn enqueue-sse-event! [registry session-id event payload]
  (when-let [q (get-in @registry [:sessions session-id :sse :queue])]
    (.offer ^LinkedBlockingQueue q {:event event
                                    :payload payload})
    true))

(defn sse-connected? [registry session-id]
  (boolean (get-in @registry [:sessions session-id :sse :queue])))

(defn poll-sse-event! [q timeout-ms]
  (.poll ^LinkedBlockingQueue q (long timeout-ms) TimeUnit/MILLISECONDS))
