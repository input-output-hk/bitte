{
  flakeClusters = (builtins.getFlake (toString ./.)).clusters;
}
