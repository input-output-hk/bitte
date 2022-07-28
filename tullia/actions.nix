{
  "bitte/ci-push" = {
    task = "build";
    io = ''
      _lib: github: {
        #repo: "input-output-hk/bitte"
        push: #branch: "bitte-tests"
      }
    '';
  };
}
