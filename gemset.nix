{
  citrus = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0l7nhk3gkm1hdchkzzhg2f70m47pc0afxfpl6mkiibc9qcpl3hjf";
      type = "gem";
    };
    version = "3.0.2";
  };
  rake = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "15whn7p9nrkxangbs9hh75q585yfn66lv0v2mhj6q6dl6x8bzr2w";
      type = "gem";
    };
    version = "13.0.6";
  };
  sshkey = {
    groups = ["default"];
    platforms = [];
    source = {
      fetchSubmodules = false;
      rev = "6fd399213edd8611c1e540064d42d16b5e712782";
      sha256 = "1q2kj62660nlggwknnb0a3gjmslan231r93v5hrhrsbwj4jgzwfa";
      type = "git";
      url = "https://github.com/bensie/sshkey";
    };
    version = "2.0.0";
  };
  toml-rb = {
    dependencies = ["citrus"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1mrr8c9agmf9l9gs63lnsqzc62x08hj673yix7bjss1kvagwjnsr";
      type = "gem";
    };
    version = "2.1.0";
  };
}
