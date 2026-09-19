package demo;

class Greeter {
    Greeter partner;

    String greeting() {
        return "hello";
    }

    String greet() {
        return greeting();
    }

    void announce() {
        greet();
        report();
    }
}
