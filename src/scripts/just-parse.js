const R = require("requirejs");

R(["../../build/phase1/js/pyret-tokenizer", "../../build/phase1/js/pyret-parser", "fs"], function(T, G, fs) {
  const data = fs.readFileSync(process.argv[2], {encoding: "utf-8"});
  const toks = T.Tokenizer;
  toks.tokenizeFrom(data);
  // while (toks.hasNext())
  //   console.log(toks.next().toString(true));
  var parsed = G.PyretGrammar.parse(toks);
  if (parsed) {
    console.log("Result:");
    G.PyretGrammar.countAndPriceAllParses(parsed);
    console.log("Count:", parsed.count, ", min cost:", parsed.minCost);
    var countParses = G.PyretGrammar.countAllParses(parsed);
    console.log("There are " + countParses + " potential parses");
    var count = 0;
    console.log("Cheapest parse:", G.PyretGrammar.constructCheapestParse(parsed).toString());
    var answer = G.PyretGrammar.constructNextParse(parsed);
    while (answer) {
      count++;
      console.log("Parse " + count + ": " + answer.parse.weight + " " + answer.parse.toString());
      answer = G.PyretGrammar.constructNextParse(parsed, undefined, answer.directions);
    }
  } else {
    console.log("Invalid parse: you screwed up.");
    console.log("Next token is " + toks.curTok.toString(true) + " at " + toks.curTok.pos.toString(true));
  }
});
