#include <iostream>
#include <thread>
#include <chrono>

#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_floating_point.hpp>
#include "fmt/format.h"
#include "nlohmann/json.hpp"
#include "yaml-cpp/yaml.h"
#include "SQLiteCpp/SQLiteCpp.h"
#include "httplib.h"

#include "au/au.hh"
#include "au/units/meters.hh"
#include "au/units/feet.hh"
#include "au/units/seconds.hh"

using namespace std;
using namespace au;
using json = nlohmann::json;

TEST_CASE("Aurora Units - unit conversions and arithmetic", "[au]")
{
    SECTION("Basic conversions")
    {
        auto length = meters(100.0);
        auto in_feet_q = length.as(feet);
        double in_feet = in_feet_q.in(feet);
        REQUIRE_THAT(in_feet, Catch::Matchers::WithinRel(328.084, 0.001));

        auto back = in_feet_q.as(meters);
        double back_to_meters = back.in(meters);
        REQUIRE_THAT(back_to_meters, Catch::Matchers::WithinRel(100.0, 0.001));
    }

    SECTION("Arithmetic with units")
    {
        auto d1 = meters(50.0);
        auto d2 = meters(30.0);
        auto sum = d1 + d2;
        REQUIRE_THAT(sum.in(meters), Catch::Matchers::WithinRel(80.0, 0.001));

        auto doubled = d1 * 2;
        REQUIRE_THAT(doubled.in(meters), Catch::Matchers::WithinRel(100.0, 0.001));
    }

    SECTION("Velocity calculation")
    {
        auto distance = meters(100.0);
        auto time = seconds(10.0);
        auto velocity = distance / time;
        REQUIRE_THAT(velocity.in(meters / second), Catch::Matchers::WithinRel(10.0, 0.001));
    }
}

TEST_CASE("nlohmann/json - parse, modify, serialize", "[json]")
{
    SECTION("Parse nested JSON")
    {
        auto j = json::parse(R"({
            "name": "test",
            "values": [1, 2, 3],
            "nested": {"key": "value"}
        })");

        REQUIRE(j["name"] == "test");
        REQUIRE(j["values"].size() == 3);
        REQUIRE(j["values"][1] == 2);
        REQUIRE(j["nested"]["key"] == "value");
    }

    SECTION("Iterate arrays")
    {
        auto j = json::parse(R"({"items": [10, 20, 30]})");
        int sum = 0;
        for (auto& item : j["items"]) {
            sum += item.get<int>();
        }
        REQUIRE(sum == 60);
    }

    SECTION("Modify and serialize")
    {
        json j;
        j["created"] = true;
        j["count"] = 42;
        j["tags"] = {"a", "b", "c"};

        string serialized = j.dump();
        auto reparsed = json::parse(serialized);

        REQUIRE(reparsed["created"] == true);
        REQUIRE(reparsed["count"] == 42);
        REQUIRE(reparsed["tags"].size() == 3);
    }
}

TEST_CASE("yaml-cpp - parse and traverse", "[yaml]")
{
    SECTION("Parse nested YAML")
    {
        YAML::Node config = YAML::Load(R"(
            database:
                host: localhost
                port: 5432
            servers:
                - name: alpha
                  weight: 10
                - name: beta
                  weight: 20
        )");

        REQUIRE(config["database"]["host"].as<string>() == "localhost");
        REQUIRE(config["database"]["port"].as<int>() == 5432);
        REQUIRE(config["servers"].size() == 2);
        REQUIRE(config["servers"][0]["name"].as<string>() == "alpha");
    }

    SECTION("Iterate sequences")
    {
        YAML::Node items = YAML::Load("[1, 2, 3, 4, 5]");
        int sum = 0;
        for (auto it = items.begin(); it != items.end(); ++it) {
            sum += it->as<int>();
        }
        REQUIRE(sum == 15);
    }

    SECTION("Type conversions")
    {
        YAML::Node node = YAML::Load(R"(
            int_val: 42
            float_val: 3.14
            bool_val: true
            str_val: hello
        )");

        REQUIRE(node["int_val"].as<int>() == 42);
        REQUIRE_THAT(node["float_val"].as<double>(), Catch::Matchers::WithinRel(3.14, 0.001));
        REQUIRE(node["bool_val"].as<bool>() == true);
        REQUIRE(node["str_val"].as<string>() == "hello");
    }
}

TEST_CASE("SQLiteCpp - CRUD and transactions", "[sqlite]")
{
    SQLite::Database db(":memory:", SQLite::OPEN_READWRITE | SQLite::OPEN_CREATE);

    SECTION("Create and insert")
    {
        db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score INTEGER)");

        SQLite::Statement insert(db, "INSERT INTO users (name, score) VALUES (?, ?)");
        insert.bind(1, "alice");
        insert.bind(2, 100);
        insert.exec();
        insert.reset();

        insert.bind(1, "bob");
        insert.bind(2, 85);
        insert.exec();

        SQLite::Statement query(db, "SELECT COUNT(*) FROM users");
        query.executeStep();
        REQUIRE(query.getColumn(0).getInt() == 2);
    }

    SECTION("Query with WHERE")
    {
        db.exec("CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price REAL)");
        db.exec("INSERT INTO products (name, price) VALUES ('widget', 9.99)");
        db.exec("INSERT INTO products (name, price) VALUES ('gadget', 19.99)");
        db.exec("INSERT INTO products (name, price) VALUES ('gizmo', 29.99)");

        SQLite::Statement query(db, "SELECT name, price FROM products WHERE price > ?");
        query.bind(1, 15.0);

        vector<string> names;
        while (query.executeStep()) {
            names.push_back(query.getColumn(0).getString());
        }

        REQUIRE(names.size() == 2);
        REQUIRE(find(names.begin(), names.end(), "gadget") != names.end());
        REQUIRE(find(names.begin(), names.end(), "gizmo") != names.end());
    }

    SECTION("Transaction rollback")
    {
        db.exec("CREATE TABLE accounts (id INTEGER PRIMARY KEY, balance INTEGER)");
        db.exec("INSERT INTO accounts (balance) VALUES (1000)");

        {
            SQLite::Transaction txn(db);
            db.exec("UPDATE accounts SET balance = 500");
            // Don't commit - transaction will rollback on scope exit
        }

        SQLite::Statement query(db, "SELECT balance FROM accounts");
        query.executeStep();
        REQUIRE(query.getColumn(0).getInt() == 1000); // Should be unchanged
    }
}

TEST_CASE("cpp-httplib - server and client", "[http]")
{
    httplib::Server svr;

    svr.Get("/api/status", [](const httplib::Request&, httplib::Response& res) {
        res.set_content(R"({"status": "ok", "code": 200})", "application/json");
    });

    svr.Post("/api/echo", [](const httplib::Request& req, httplib::Response& res) {
        res.set_content(req.body, "text/plain");
    });

    thread server_thread([&svr]() {
        svr.listen("127.0.0.1", 18080);
    });

    // Wait for server to start
    while (!svr.is_running()) {
        this_thread::sleep_for(chrono::milliseconds(10));
    }

    SECTION("GET request returns JSON")
    {
        httplib::Client cli("127.0.0.1", 18080);
        auto res = cli.Get("/api/status");

        REQUIRE(res);
        REQUIRE(res->status == 200);

        auto j = json::parse(res->body);
        REQUIRE(j["status"] == "ok");
        REQUIRE(j["code"] == 200);
    }

    SECTION("POST echoes body")
    {
        httplib::Client cli("127.0.0.1", 18080);
        auto res = cli.Post("/api/echo", "hello world", "text/plain");

        REQUIRE(res);
        REQUIRE(res->status == 200);
        REQUIRE(res->body == "hello world");
    }

    svr.stop();
    server_thread.join();
}

TEST_CASE("cpp-httplib - HTTPS client", "[https]")
{
    httplib::SSLClient cli("httpbin.org", 443);
    cli.set_connection_timeout(5);
    cli.set_read_timeout(5);

    auto res = cli.Get("/get");

    REQUIRE(res);
    REQUIRE(res->status == 200);

    auto j = json::parse(res->body);
    REQUIRE(j.contains("url"));
}

TEST_CASE("fmt - string formatting", "[fmt]")
{
    SECTION("Basic formatting")
    {
        string result = fmt::format("Hello, {}!", "world");
        REQUIRE(result == "Hello, world!");
    }

    SECTION("Positional args")
    {
        string result = fmt::format("{1} before {0}", "second", "first");
        REQUIRE(result == "first before second");
    }

    SECTION("Numeric formatting")
    {
        string result = fmt::format("{:.2f}", 3.14159);
        REQUIRE(result == "3.14");

        result = fmt::format("{:08d}", 42);
        REQUIRE(result == "00000042");
    }
}
