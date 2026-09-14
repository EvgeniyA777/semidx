package demo;

class Greeter {
    Greeter partner;

    String greeting() {
        return "hello";
    }

    String greet() {
        return greeting();
    }

    void report() {
    }

    void announce() {
        greet();
        report();
    }
}
