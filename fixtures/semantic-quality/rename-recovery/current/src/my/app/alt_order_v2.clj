(ns my.app.alt-order-v2)

(defn validate-alt-order [order]
  (assoc order :alt true))
