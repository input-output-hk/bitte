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
      sha256 = "1iik52mf9ky4cgs38fp2m8r6skdkq1yz23vh18lk95fhbcxb6a67";
      type = "gem";
    };
    version = "13.0.3";
  };
  sshkey = {
    groups = ["default"];
    platforms = [];
    source = {
      fetchSubmodules = false;
      rev = "b7762f36f29c0a79234e4f87ca13cb0379290a80";
      sha256 = "1iw3p4j6g0ym5z8v5v12yx5vgzf5snp3gadixn7pps55gpih6nsj";
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
      sha256 = "0x5j95w28vj85bzw98g1dyd4gm7xpli2fdvwwrgwlay7gb3wc5jh";
      type = "gem";
    };
    version = "2.0.1";
  };
}
