package demo;

class Greeter {
    Greeter partner;

    String greeting() {
        return "hello";
    }

    String greet() {
        return greeting();
    }

    String farewell() {
        return "bye";
    }

    void announce() {
        greet();
        report();
    }
}
