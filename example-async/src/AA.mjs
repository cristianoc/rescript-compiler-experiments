// Generated by ReScript, PLEASE EDIT WITH CARE

import * as Js_exn from "rescript/lib/es6/js_exn.js";
import * as Belt_List from "rescript/lib/es6/belt_List.js";
import * as Caml_array from "rescript/lib/es6/caml_array.js";
import * as Caml_option from "rescript/lib/es6/caml_option.js";
import * as Caml_exceptions from "rescript/lib/es6/caml_exceptions.js";
import * as Caml_js_exceptions from "rescript/lib/es6/caml_js_exceptions.js";

var tests = [];

function addTest(t) {
  tests.push(t);
}

function addTest1(t, x) {
  tests.push(function () {
        return t(x);
      });
}

async function foo(x, y) {
  return x + y | 0;
}

async function bar(ff) {
  var a = await ff(3, 4);
  var b = await foo(5, 6);
  return a + b | 0;
}

async function baz() {
  return await bar(foo);
}

async function testBaz() {
  var n = await baz();
  console.log("baz returned", n);
}

tests.push(testBaz);

var E = /* @__PURE__ */Caml_exceptions.create("AA.E");

async function e1() {
  throw {
        RE_EXN_ID: E,
        _1: 1000,
        Error: new Error()
      };
}

async function e2() {
  return Js_exn.raiseError("Some JS error");
}

async function e3() {
  return await e1();
}

async function e4() {
  return await e2();
}

var e5 = (function() { return Promise.reject(new Error('fail')) });

async function testTryCatch(fn) {
  try {
    return await fn();
  }
  catch (raw_n){
    var n = Caml_js_exceptions.internalToOCamlException(raw_n);
    if (n.RE_EXN_ID === E) {
      console.log("testTryCatch: E", n._1);
      return ;
    }
    if (n.RE_EXN_ID === "JsError") {
      console.log("testTryCatch: JsError");
      return ;
    }
    throw n;
  }
}

addTest1(testTryCatch, e1);

addTest1(testTryCatch, e2);

addTest1(testTryCatch, e3);

addTest1(testTryCatch, e4);

addTest1(testTryCatch, e5);

async function singlePromise(x) {
  return x + 1 | 0;
}

async function nestedPromise(x) {
  var x$1 = singlePromise(x + 1 | 0);
  [Promise.resolve(x$1)];
  return 32;
}

function $$fetch$1(url) {
  return fetch(url);
}

function status(response) {
  return response.status;
}

var Fetch = {
  $$fetch: $$fetch$1,
  status: status
};

var explainError = ((e)=>e.toString());

async function testFetch(url) {
  var response;
  try {
    response = await fetch(url);
  }
  catch (raw_e){
    var e = Caml_js_exceptions.internalToOCamlException(raw_e);
    if (e.RE_EXN_ID === "JsError") {
      console.log("Fetch returned an error:", explainError(e._1));
      return ;
    }
    throw e;
  }
  var status = response.status;
  console.log("Fetch returned status:", status);
}

addTest1(testFetch, "https://www.google.com/sdkjdkghdsg");

addTest1(testFetch, "https://www.google.comsdkjdkghdsg");

async function withCallback() {
  return async function (x) {
    return await Promise.resolve(x) + 1 | 0;
  };
}

async function testWithCallback() {
  console.log("callback returned", await (await withCallback())(3));
}

tests.push(testWithCallback);

async function map(l, f) {
  var loop = async function (l, acc) {
    if (l) {
      return await loop(l.tl, {
                  hd: await l.hd,
                  tl: acc
                });
    } else {
      return acc;
    }
  };
  return await loop(Belt_List.mapReverse(l, (function (x) {
                    return f(x);
                  })), /* [] */0);
}

var AsyncList = {
  map: map
};

var counter = {
  contents: 0
};

async function ff(url) {
  var response = await fetch(url);
  counter.contents = counter.contents + 1 | 0;
  return [
          counter.contents,
          response.status
        ];
}

async function testFetchMany() {
  return Belt_List.forEach(await map({
                  hd: "https://www.google.com",
                  tl: {
                    hd: "https://www.google.com",
                    tl: {
                      hd: "https://www.google.com",
                      tl: {
                        hd: "https://www.google.com",
                        tl: {
                          hd: "https://www.google.com",
                          tl: /* [] */0
                        }
                      }
                    }
                  }
                }, ff), (function (param) {
                console.log("Fetched", param[0], param[1]);
              }));
}

tests.push(testFetchMany);

async function $$fetch$2(url) {
  var response;
  try {
    response = await fetch(url);
  }
  catch (raw_e){
    var e = Caml_js_exceptions.internalToOCamlException(raw_e);
    if (e.RE_EXN_ID === "JsError") {
      return {
              TAG: /* Error */1,
              _0: e._1
            };
    }
    throw e;
  }
  return {
          TAG: /* Ok */0,
          _0: response
        };
}

var FetchResult = {
  $$fetch: $$fetch$2
};

function nextFetch(_response) {
  return "https://github.com/";
}

async function testFetchWithResult() {
  var response1 = await $$fetch$2("https://www.google.com");
  if (response1.TAG !== /* Ok */0) {
    return ;
  }
  var response1$1 = response1._0;
  console.log("FetchResult response1", response1$1.status);
  var url = nextFetch(response1$1);
  if (url === undefined) {
    return ;
  }
  var response2 = await $$fetch$2(url);
  if (response2.TAG !== /* Ok */0) {
    return ;
  }
  console.log("FetchResult response2", response2._0.status);
}

tests.push(testFetchWithResult);

async function runAllTests(n) {
  if (n >= 0 && n < tests.length) {
    await Caml_array.get(tests, n)();
    return await runAllTests(n + 1 | 0);
  }
  
}

runAllTests(0);

async function bb(x) {
  return await x;
}

async function cc(x, yOpt, z) {
  var y = yOpt !== undefined ? Caml_option.valFromOption(yOpt) : x;
  return (await x + await y | 0) + await z | 0;
}

async function dd(x, y) {
  return await x + await y | 0;
}

async function ee(x, y) {
  return await x + await y | 0;
}

var fetchAndCount = ff;

export {
  tests ,
  addTest ,
  addTest1 ,
  foo ,
  bar ,
  baz ,
  testBaz ,
  E ,
  e1 ,
  e2 ,
  e3 ,
  e4 ,
  e5 ,
  testTryCatch ,
  singlePromise ,
  nestedPromise ,
  Fetch ,
  explainError ,
  testFetch ,
  withCallback ,
  testWithCallback ,
  AsyncList ,
  fetchAndCount ,
  testFetchMany ,
  FetchResult ,
  nextFetch ,
  testFetchWithResult ,
  runAllTests ,
  bb ,
  cc ,
  dd ,
  ee ,
}
/*  Not a pure module */
