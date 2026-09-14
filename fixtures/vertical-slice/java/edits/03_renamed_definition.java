package demo;

class Greeter {
    Greeter partner;

    String salutation() {
        return "hello";
    }

    String greet() {
        return salutation();
    }

    void announce() {
        greet();
        report();
    }
}
