(ns demo.greeter)

(def salutation "hello")

(defn greet []
  (decorate salutation))
