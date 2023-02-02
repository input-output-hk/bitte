{
  cell,
  inputs,
}: {
  "bitte/ci" = {
    task = "build";
    io = ''
      let github = {
        #input: "GitHub event"
        #repo: "input-output-hk/bitte"
      }
      #lib.merge
      #ios: [
        #lib.io.github_push & github & {#default_branch: true},
        #lib.io.github_pr   & github,
      ]
    '';
  };
}
