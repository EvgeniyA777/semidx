(ns demo.greeter)

(def salutation "hello")

(defn greet []
  (str salutation "!"))

(defn announce []
  (greet)
  (report))
