let
  ciInputName = "GitHub event";
in {
  "bitte/ci" = {
    task = "build";
    io = ''
      let github = {
        #input: "${ciInputName}"
        #repo: "input-output-hk/bitte"
      }
      #lib.merge
      #ios: [
        #lib.io.github_pr   & github,
        #lib.io.github_push & github,
      ]
    '';
  };
}
