# This is shamelessly pligiarized from here:
# https://gist.githubusercontent.com/duairc/5c9bb3c922e5d501a1edb9e7b3b845ba/raw/3885f7cd9ed0a746a9d675da6f265d41e9fd6704/net.nix
{ lib ? null, ... }:

let

  net = {
    ip = {

      # add :: (ip | mac | integer) -> ip -> ip
      #
      # Examples:
      #
      # Adding integer to IPv4:
      # > net.ip.add 100 "10.0.0.1"
      # "10.0.0.101"
      #
      # Adding IPv4 to IPv4:
      # > net.ip.add "127.0.0.1" "10.0.0.1"
      # "137.0.0.2"
      #
      # Adding IPv6 to IPv4:
      # > net.ip.add "::cafe:beef" "10.0.0.1"
      # "212.254.186.191"
      #
      # Adding MAC to IPv4 (overflows):
      # > net.ip.add "fe:ed:fa:ce:f0:0d" "10.0.0.1"
      # "4.206.240.14"
      #
      # Adding integer to IPv6:
      # > net.ip.add 100 "dead:cafe:beef::"
      # "dead:cafe:beef::64"
      #
      # Adding IPv4 to to IPv6:
      # > net.ip.add "127.0.0.1" "dead:cafe:beef::"
      # "dead:cafe:beef::7f00:1"
      #
      # Adding MAC to IPv6:
      # > net.ip.add "fe:ed:fa:ce:f0:0d" "dead:cafe:beef::"
      # "dead:cafe:beef::feed:face:f00d"
      add = delta: ip:
        let
          function = "net.ip.add";
          delta' = typechecks.numeric function "delta" delta;
          ip' = typechecks.ip function "ip" ip;
        in
          builders.ip (implementations.ip.add delta' ip');

      # diff :: ip -> ip -> (integer | ipv6)
      #
      # net.ip.diff is the reverse of net.ip.add:
      #
      # net.ip.diff (net.ip.add a b) a = b
      # net.ip.diff (net.ip.add a b) b = a
      #
      # The difference between net.ip.diff and net.ip.subtract is that
      # net.ip.diff will try its best to return an integer (falling back
      # to an IPv6 if the result is too big to fit in an integer). This is
      # useful if you have two hosts that you know are on the same network
      # and you just want to calculate the offset between them — a result
      # like "0.0.0.10" is not very useful (which is what you would get
      # from net.ip.subtract).
      diff = minuend: subtrahend:
        let
          function = "net.ip.diff";
          minuend' = typechecks.ip function "minuend" minuend;
          subtrahend' = typechecks.ip function "subtrahend" subtrahend;
          result = implementations.ip.diff minuend' subtrahend';
        in
          if result ? ipv6
          then builders.ipv6 result
          else result;

      # subtract :: (ip | mac | integer) -> ip -> ip
      #
      # net.ip.subtract is also the reverse of net.ip.add:
      #
      # net.ip.subtract a (net.ip.add a b) = b
      # net.ip.subtract b (net.ip.add a b) = a
      #
      # The difference between net.ip.subtract and net.ip.diff is that
      # net.ip.subtract will always return the same type as its "ip"
      # parameter. Its implementation takes the "delta" parameter,
      # coerces it to be the same type as the "ip" paramter, negates it
      # (using two's complement), and then adds it to "ip".
      subtract = delta: ip:
        let
          function = "net.ip.subtract";
          delta' = typechecks.numeric function "delta" delta;
          ip' = typechecks.ip function "ip" ip;
        in
          builders.ip (implementations.ip.subtract delta' ip');
    };

    mac = {

      # add :: (ip | mac | integer) -> mac -> mac
      #
      # Examples:
      #
      # Adding integer to MAC:
      # > net.mac.add 100 "fe:ed:fa:ce:f0:0d"
      # "fe:ed:fa:ce:f0:71"
      #
      # Adding IPv4 to MAC:
      # > net.mac.add "127.0.0.1" "fe:ed:fa:ce:f0:0d"
      # "fe:ee:79:ce:f0:0e"
      #
      # Adding IPv6 to MAC:
      # > net.mac.add "::cafe:beef" "fe:ed:fa:ce:f0:0d"
      # "fe:ee:c5:cd:aa:cb
      #
      # Adding MAC to MAC:
      # > net.mac.add "fe:ed:fa:00:00:00" "00:00:00:ce:f0:0d"
      # "fe:ed:fa:ce:f0:0d"
      add = delta: mac:
        let
          function = "net.mac.add";
          delta' = typechecks.numeric function "delta" delta;
          mac' = typechecks.mac function "mac" mac;
        in
          builders.mac (implementations.mac.add delta' mac');

      # diff :: mac -> mac -> integer
      #
      # net.mac.diff is the reverse of net.mac.add:
      #
      # net.mac.diff (net.mac.add a b) a = b
      # net.mac.diff (net.mac.add a b) b = a
      #
      # The difference between net.mac.diff and net.mac.subtract is that
      # net.mac.diff will always return an integer.
      diff = minuend: subtrahend:
        let
          function = "net.mac.diff";
          minuend' = typechecks.mac function "minuend" minuend;
          subtrahend' = typechecks.mac function "subtrahend" subtrahend;
        in
          implementations.mac.diff minuend' subtrahend';

      # subtract :: (ip | mac | integer) -> mac -> mac
      #
      # net.mac.subtract is also the reverse of net.ip.add:
      #
      # net.mac.subtract a (net.mac.add a b) = b
      # net.mac.subtract b (net.mac.add a b) = a
      #
      # The difference between net.mac.subtract and net.mac.diff is that
      # net.mac.subtract will always return a MAC address.
      subtract = delta: mac:
        let
          function = "net.mac.subtract";
          delta' = typechecks.numeric function "delta" delta;
          mac' = typechecks.mac function "mac" mac;
        in
          builders.mac (implementations.mac.subtract delta' mac');
    };

    cidr = {
      # add :: (ip | mac | integer) -> cidr -> cidr
      #
      # > net.cidr.add 2 "127.0.0.0/8"
      # "129.0.0.0/8"
      #
      # > net.cidr.add (-2) "127.0.0.0/8"
      # "125.0.0.0/8"
      add = delta: cidr:
        let
          function = "net.cidr.add";
          delta' = typechecks.numeric function "delta" delta;
          cidr' = typechecks.cidr function "cidr" cidr;
        in
          builders.cidr (implementations.cidr.add delta' cidr');

      # child :: cidr -> cidr -> bool
      #
      # > net.cidr.child "10.10.10.0/24" "10.0.0.0/8"
      # true
      #
      # > net.cidr.child "127.0.0.0/8" "10.0.0.0/8"
      # false
      child = subcidr: cidr:
        let
          function = "net.cidr.child";
          subcidr' = typechecks.cidr function "subcidr" subcidr;
          cidr' = typechecks.cidr function "cidr" cidr;
        in
          implementations.cidr.child subcidr' cidr';

      # contains :: ip -> cidr -> bool
      #
      # > net.cidr.contains "127.0.0.1" "127.0.0.0/8"
      # true
      #
      # > net.cidr.contains "127.0.0.1" "192.168.0.0/16"
      # false
      contains = ip: cidr:
        let
          function = "net.cidr.contains";
          ip' = typechecks.ip function "ip" ip;
          cidr' = typechecks.cidr function "cidr" cidr;
        in
          implementations.cidr.contains ip' cidr';

      # capacity :: cidr -> integer
      #
      # > net.cidr.capacity "172.16.0.0/12"
      # 1048576
      #
      # > net.cidr.capacity "dead:cafe:beef::/96"
      # 4294967296
      #
      # > net.cidr.capacity "dead:cafe:beef::/48" (saturates to maxBound)
      # 9223372036854775807
      capacity = cidr:
        let
          function = "net.cidr.capacity";
          cidr' = typechecks.cidr function "cidr" cidr;
        in
          implementations.cidr.capacity cidr';

      # host :: (ip | mac | integer) -> cidr -> ip
      #
      # > net.cidr.host 10000 "10.0.0.0/8"
      # 10.0.39.16
      #
      # > net.cidr.host 10000 "dead:cafe:beef::/64"
      # "dead:cafe:beef::2710"
      #
      # net.cidr.host "127.0.0.1" "dead:cafe:beef::/48"
      # > "dead:cafe:beef::7f00:1"
      #
      # Inpsired by:
      # https://www.terraform.io/docs/configuration/functions/cidrhost.html
      host = hostnum: cidr:
        let
          function = "net.cidr.host";
          hostnum' = typechecks.numeric function "hostnum" hostnum;
          cidr' = typechecks.cidr function "cidr" cidr;
        in
          builders.ip (implementations.cidr.host hostnum' cidr');

      # length :: cidr -> integer
      #
      # > net.cidr.prefix "127.0.0.0/8"
      # 8
      #
      # > net.cidr.prefix "dead:cafe:beef::/48"
      # 48
      length = cidr:
        let
          function = "net.cidr.length";
          cidr' = typechecks.cidr function "cidr" cidr;
        in
          implementations.cidr.length cidr';

      # make :: integer -> ip -> cidr
      #
      # > net.cidr.make 24 "192.168.0.150"
      # "192.168.0.0/24"
      #
      # > net.cidr.make 40 "dead:cafe:beef::feed:face:f00d"
      # "dead:cafe:be00::/40"
      make = length: base:
        let
          function = "net.cidr.make";
          length' = typechecks.int function "length" length;
          base' = typechecks.ip function "base" base;
        in
          builders.cidr (implementations.cidr.make length' base');

      # netmask :: cidr -> ip
      #
      # > net.cidr.netmask "192.168.0.0/24"
      # "255.255.255.0"
      #
      # > net.cidr.netmask "dead:cafe:beef::/64"
      # "ffff:ffff:ffff:ffff::"
      netmask = cidr:
        let
          function = "net.cidr.netmask";
          cidr' = typechecks.cidr function "cidr" cidr;
        in
          builders.ip (implementations.cidr.netmask cidr');

      # size :: cidr -> integer
      #
      # > net.cidr.prefix "127.0.0.0/8"
      # 24
      #
      # > net.cidr.prefix "dead:cafe:beef::/48"
      # 80
      size = cidr:
        let
          function = "net.cidr.size";
          cidr' = typechecks.cidr function "cidr" cidr;
        in
          implementations.cidr.size cidr';

      # subnet :: integer -> (ip | mac | integer) -> cidr -> cidr
      #
      # > net.cidr.subnet 4 2 "172.16.0.0/12"
      # "172.18.0.0/16"
      #
      # > net.cidr.subnet 4 15 "10.1.2.0/24"
      # "10.1.2.240/28"
      #
      # > net.cidr.subnet 16 162 "fd00:fd12:3456:7890::/56"
      # "fd00:fd12:3456:7800:a200::/72"
      #
      # Inspired by:
      # https://www.terraform.io/docs/configuration/functions/cidrsubnet.html
      subnet = length: netnum: cidr:
        let
          function = "net.cidr.subnet";
          length' = typechecks.int function "length" length;
          netnum' = typechecks.numeric function "netnum" netnum;
          cidr' = typechecks.cidr function "cidr" cidr;
        in
          builders.cidr (implementations.cidr.subnet length' netnum' cidr');

    };
  } // (
    if builtins.isNull lib then {} else {
      types =
        let

          mkParsedOptionType = { name, description, parser, builder }:
            let
              normalize = def: def // {
                value = builder (parser def.value);
              };
            in
              lib.mkOptionType {
                inherit name description;
                check = x: builtins.isString x && parser x != null;
                merge = loc: defs: lib.mergeEqualOption loc (map normalize defs);
              };

          dependent-ip = type: cidr:
            let
              cidrs =
                if builtins.isList cidr
                then cidr
                else [ cidr ];
            in
              lib.types.addCheck type (i: lib.any (net.cidr.contains i) cidrs) // {
                description = type.description + " in ${builtins.concatStringsSep " or " cidrs}";
              };

          dependent-cidr = type: cidr:
            let
              cidrs =
                if builtins.isList cidr
                then cidr
                else [ cidr ];
            in
              lib.types.addCheck type (i: lib.any (net.cidr.child i) cidrs) // {
                description = type.description + " in ${builtins.concatStringsSep " or " cidrs}";
              };

        in
          rec {

            ip = mkParsedOptionType {
              name = "ip";
              description = "IPv4 or IPv6 address";
              parser = parsers.ip;
              builder = builders.ip;
            };

            ip-in = dependent-ip ip;

            ipv4 = mkParsedOptionType {
              name = "ipv4";
              description = "IPv4 address";
              parser = parsers.ipv4;
              builder = builders.ipv4;
            };

            ipv4-in = dependent-ip ipv4;

            ipv6 = mkParsedOptionType {
              name = "ipv6";
              description = "IPv6 address";
              parser = parsers.ipv6;
              builder = builders.ipv6;
            };

            ipv6-in = dependent-ip ipv6;

            cidr = mkParsedOptionType {
              name = "cidr";
              description = "IPv4 or IPv6 address range in CIDR notation";
              parser = parsers.cidr;
              builder = builders.cidr;
            };

            cidr-in = dependent-cidr cidr;

            cidrv4 = mkParsedOptionType {
              name = "cidrv4";
              description = "IPv4 address range in CIDR notation";
              parser = parsers.cidrv4;
              builder = builders.cidrv4;
            };

            cidrv4-in = dependent-cidr cidrv4;

            cidrv6 = mkParsedOptionType {
              name = "cidrv6";
              description = "IPv6 address range in CIDR notation";
              parser = parsers.cidrv6;
              builder = builders.cidrv6;
            };

            cidrv6-in = dependent-cidr cidrv6;

            mac = mkParsedOptionType {
              name = "mac";
              description = "MAC address";
              parser = parsers.mac;
              builder = builders.mac;
            };

          };
    }
  );

  list = {
    cons = a: b: [ a ] ++ b;
  };

  bit =
    let
      shift = n: x:
        if n < 0
        then x * math.pow 2 (-n)
        else
          let
            safeDiv = n: d: if d == 0 then 0 else n / d;
            d = math.pow 2 n;
          in
            if x < 0
            then not (safeDiv (not x) d)
            else safeDiv x d;

      left = n: shift (-n);

      right = shift;

      and = builtins.bitAnd;

      or = builtins.bitOr;

      xor = builtins.bitXor;

      not = xor (-1);

      mask = n: and (left n 1 - 1);
    in
      {
        inherit left right and or xor not mask;
      };

  math = rec {
    max = a: b:
      if a > b
      then a
      else b;

    min = a: b:
      if a < b
      then a
      else b;

    clamp = a: b: c: max a (min b c);

    pow = x: n:
      if n == 0
      then 1
      else if bit.and n 1 != 0
      then x * pow (x * x) ((n - 1) / 2)
      else pow (x * x) (n / 2);
  };

  parsers =
    let

      # fmap :: (a -> b) -> parser a -> parser b
      fmap = f: ma: bind ma (a: pure (f a));

      # pure :: a -> parser a
      pure = a: string: {
        leftovers = string;
        result = a;
      };

      # liftA2 :: (a -> b -> c) -> parser a -> parser b -> parser c
      liftA2 = f: ma: mb: bind ma (a: bind mb (b: pure (f a b)));
      liftA3 = f: a: b: ap (liftA2 f a b);
      liftA4 = f: a: b: c: ap (liftA3 f a b c);
      liftA5 = f: a: b: c: d: ap (liftA4 f a b c d);
      liftA6 = f: a: b: c: d: e: ap (liftA5 f a b c d e);

      # ap :: parser (a -> b) -> parser a -> parser b
      ap = liftA2 (a: a);

      # then_ :: parser a -> parser b -> parser b
      then_ = liftA2 (a: b: b);

      # empty :: parser a
      empty = string: null;

      # alt :: parser a -> parser a -> parser a
      alt = left: right: string:
        let
          result = left string;
        in
          if builtins.isNull result
          then right string
          else result;

      # guard :: bool -> parser {}
      guard = condition: if condition then pure {} else empty;

      # mfilter :: (a -> bool) -> parser a -> parser a
      mfilter = f: parser: bind parser (a: then_ (guard (f a)) (pure a));

      # some :: parser a -> parser [a]
      some = v: liftA2 list.cons v (many v);

      # many :: parser a -> parser [a]
      many = v: alt (some v) (pure []);

      # bind :: parser a -> (a -> parser b) -> parser b
      bind = parser: f: string:
        let
          a = parser string;
        in
          if builtins.isNull a
          then null
          else f a.result a.leftovers;

      # run :: parser a -> string -> maybe a
      run = parser: string:
        let
          result = parser string;
        in
          if builtins.isNull result || result.leftovers != ""
          then null
          else result.result;

      next = string:
        if string == ""
        then null
        else {
          leftovers = builtins.substring 1 (-1) string;
          result = builtins.substring 0 1 string;
        };

      # Count how many characters were consumed by a parser
      count = parser: string:
        let
          result = parser string;
        in
          if builtins.isNull result
          then null
          else result // {
            result = {
              inherit (result) result;
              count = with result;
                builtins.stringLength string - builtins.stringLength leftovers;
            };
          };

      # Limit the parser to n characters at most
      limit = n: parser:
        fmap (a: a.result) (mfilter (a: a.count <= n) (count parser));

      # Ensure the parser consumes exactly n characters
      exactly = n: parser:
        fmap (a: a.result) (mfilter (a: a.count == n) (count parser));

      char = c: bind next (c': guard (c == c'));

      string = css:
        if css == ""
        then pure {}
        else
          let
            c = builtins.substring 0 1 css;
            cs = builtins.substring 1 (-1) css;
          in
            then_ (char c) (string cs);

      digit = set: bind next (
        c: then_
          (guard (builtins.hasAttr c set))
          (pure (builtins.getAttr c set))
      );

      decimalDigits = {
        "0" = 0;
        "1" = 1;
        "2" = 2;
        "3" = 3;
        "4" = 4;
        "5" = 5;
        "6" = 6;
        "7" = 7;
        "8" = 8;
        "9" = 9;
      };

      hexadecimalDigits = decimalDigits // {
        "a" = 10;
        "b" = 11;
        "c" = 12;
        "d" = 13;
        "e" = 14;
        "f" = 15;
        "A" = 10;
        "B" = 11;
        "C" = 12;
        "D" = 13;
        "E" = 14;
        "F" = 15;
      };

      fromDecimalDigits = builtins.foldl' (a: c: a * 10 + c) 0;
      fromHexadecimalDigits = builtins.foldl' (a: bit.or (bit.left 4 a)) 0;

      # disallow leading zeros
      decimal = bind (digit decimalDigits) (
        n:
          if n == 0
          then pure 0
          else fmap
            (ns: fromDecimalDigits (list.cons n ns))
            (many (digit decimalDigits))
      );

      hexadecimal = fmap fromHexadecimalDigits (some (digit hexadecimalDigits));

      ipv4 =
        let
          dot = char ".";

          octet = mfilter (n: n < 256) decimal;

          octet' = then_ dot octet;

          fromOctets = a: b: c: d: {
            ipv4 = bit.or (bit.left 8 (bit.or (bit.left 8 (bit.or (bit.left 8 a) b)) c)) d;
          };
        in
          liftA4 fromOctets octet octet' octet' octet';

      # This is more or less a literal translation of
      # https://hackage.haskell.org/package/ip/docs/src/Net.IPv6.html#parser
      ipv6 =
        let
          colon = char ":";

          hextet = limit 4 hexadecimal;

          hextet' = then_ colon hextet;

          fromHextets = hextets:
            if builtins.length hextets != 8
            then empty
            else
              let
                a = builtins.elemAt hextets 0;
                b = builtins.elemAt hextets 1;
                c = builtins.elemAt hextets 2;
                d = builtins.elemAt hextets 3;
                e = builtins.elemAt hextets 4;
                f = builtins.elemAt hextets 5;
                g = builtins.elemAt hextets 6;
                h = builtins.elemAt hextets 7;
              in
                pure {
                  ipv6 = {
                    a = bit.or (bit.left 16 a) b;
                    b = bit.or (bit.left 16 c) d;
                    c = bit.or (bit.left 16 e) f;
                    d = bit.or (bit.left 16 g) h;
                  };
                };

          ipv4' = fmap
            (
              address:
                let
                  upper = bit.right 16 address.ipv4;
                  lower = bit.mask 16 address.ipv4;
                in
                  [ upper lower ]
            )
            ipv4;

          part = n:
            let
              n' = n + 1;
              hex = liftA2 list.cons hextet
                (
                  then_ colon
                    (
                      alt
                        (then_ colon (doubleColon n'))
                        (part n')
                    )
                );
            in
              if n == 7
              then fmap (a: [ a ]) hextet
              else
                if n == 6
                then alt ipv4' hex
                else hex;

          doubleColon = n:
            bind (alt afterDoubleColon (pure [])) (
              rest:
                let
                  missing = 8 - n - builtins.length rest;
                in
                  if missing < 0
                  then empty
                  else pure (builtins.genList (_: 0) missing ++ rest)
            );

          afterDoubleColon =
            alt ipv4'
              (
                liftA2 list.cons hextet
                  (
                    alt
                      (then_ colon afterDoubleColon)
                      (pure [])
                  )
              );

        in
          bind
            (
              alt
                (
                  then_
                    (string "::")
                    (doubleColon 0)
                )
                (part 0)
            )
            fromHextets;

      cidrv4 =
        liftA2
          (base: length: implementations.cidr.make length base)
          ipv4
          (then_ (char "/") (mfilter (n: n <= 32) decimal));

      cidrv6 =
        liftA2
          (base: length: implementations.cidr.make length base)
          ipv6
          (then_ (char "/") (mfilter (n: n <= 128) decimal));

      mac =
        let
          colon = char ":";

          octet = exactly 2 hexadecimal;

          octet' = then_ colon octet;

          fromOctets = a: b: c: d: e: f: {
            mac = bit.or (bit.left 8 (bit.or (bit.left 8 (bit.or (bit.left 8 (bit.or (bit.left 8 (bit.or (bit.left 8 a) b)) c)) d)) e)) f;
          };
        in
          liftA6 fromOctets octet octet' octet' octet' octet' octet';

    in
      {
        ipv4 = run ipv4;
        ipv6 = run ipv6;
        ip = run (alt ipv4 ipv6);
        cidrv4 = run cidrv4;
        cidrv6 = run cidrv6;
        cidr = run (alt cidrv4 cidrv6);
        mac = run mac;
        numeric = run (alt (alt ipv4 ipv6) mac);
      };

  builders =
    let

      ipv4 = address:
        let
          abcd = address.ipv4;
          abc = bit.right 8 abcd;
          ab = bit.right 8 abc;
          a = bit.right 8 ab;
          b = bit.mask 8 ab;
          c = bit.mask 8 abc;
          d = bit.mask 8 abcd;
        in
          builtins.concatStringsSep "." (map toString [ a b c d ]);

      # This is more or less a literal translation of
      # https://hackage.haskell.org/package/ip/docs/src/Net.IPv6.html#encode
      ipv6 = address:
        let

          digits = "0123456789abcdef";

          toHexString = n:
            let
              rest = bit.right 4 n;
              current = bit.mask 4 n;
              prefix =
                if rest == 0
                then ""
                else toHexString rest;
            in
              "${prefix}${builtins.substring current 1 digits}";

        in
          if (with address.ipv6; a == 0 && b == 0 && c == 0 && d > 65535)
          then "::${ipv4 { ipv4 = address.ipv6.d; }}"
          else
            if (with address.ipv6; a == 0 && b == 0 && c == 65535)
            then "::ffff:${ipv4 { ipv4 = address.ipv6.d; }}"
            else
              let

                a = bit.right 16 address.ipv6.a;
                b = bit.mask 16 address.ipv6.a;
                c = bit.right 16 address.ipv6.b;
                d = bit.mask 16 address.ipv6.b;
                e = bit.right 16 address.ipv6.c;
                f = bit.mask 16 address.ipv6.c;
                g = bit.right 16 address.ipv6.d;
                h = bit.mask 16 address.ipv6.d;

                hextets = [ a b c d e f g h ];

                # calculate the position and size of the longest sequence of
                # zeroes within the list of hextets
                longest =
                  let
                    go = i: current: best:
                      if i < builtins.length hextets
                      then
                        let
                          n = builtins.elemAt hextets i;

                          current' =
                            if n == 0
                            then
                              if builtins.isNull current
                              then {
                                size = 1;
                                position = i;
                              }
                              else current // {
                                size = current.size + 1;
                              }
                            else null;

                          best' =
                            if n == 0
                            then
                              if builtins.isNull best
                              then current'
                              else
                                if current'.size > best.size
                                then current'
                                else best
                            else best;
                        in
                          go (i + 1) current' best'
                      else best;
                  in
                    go 0 null null;

                format = hextets:
                  builtins.concatStringsSep ":" (map toHexString hextets);
              in
                if builtins.isNull longest
                then format hextets
                else
                  let
                    sublist = i: length: xs:
                      map
                        (builtins.elemAt xs)
                        (builtins.genList (x: x + i) length);

                    end = longest.position + longest.size;

                    before = sublist 0 longest.position hextets;

                    after = sublist end (builtins.length hextets - end) hextets;
                  in
                    "${format before}::${format after}";

      ip = address:
        if address ? ipv4
        then ipv4 address
        else ipv6 address;

      cidrv4 = cidr:
        "${ipv4 cidr.base}/${toString cidr.length}";

      cidrv6 = cidr:
        "${ipv6 cidr.base}/${toString cidr.length}";

      cidr = cidr:
        "${ip cidr.base}/${toString cidr.length}";

      mac = address:
        let
          digits = "0123456789abcdef";
          octet = n:
            let
              upper = bit.right 4 n;
              lower = bit.mask 4 n;
            in
              "${builtins.substring upper 1 digits}${builtins.substring lower 1 digits}";
        in
          let
            a = bit.mask 8 (bit.right 40 address.mac);
            b = bit.mask 8 (bit.right 32 address.mac);
            c = bit.mask 8 (bit.right 24 address.mac);
            d = bit.mask 8 (bit.right 16 address.mac);
            e = bit.mask 8 (bit.right 8 address.mac);
            f = bit.mask 8 (bit.right 0 address.mac);
          in
            "${octet a}:${octet b}:${octet c}:${octet d}:${octet e}:${octet f}";

    in
      {
        inherit ipv4 ipv6 ip cidrv4 cidrv6 cidr mac;
      };

  arithmetic = rec {
    # or :: (ip | mac | integer) -> (ip | mac | integer) -> (ip | mac | integer)
    or = a_: b:
      let
        a = coerce b a_;
      in
        if a ? ipv6
        then {
          ipv6 = {
            a = bit.or a.ipv6.a b.ipv6.a;
            b = bit.or a.ipv6.b b.ipv6.b;
            c = bit.or a.ipv6.c b.ipv6.c;
            d = bit.or a.ipv6.d b.ipv6.d;
          };
        }
        else if a ? ipv4
        then {
          ipv4 = bit.or a.ipv4 b.ipv4;
        }
        else if a ? mac
        then {
          mac = bit.or a.mac b.mac;
        }
        else bit.or a b;

    # and :: (ip | mac | integer) -> (ip | mac | integer) -> (ip | mac | integer)
    and = a_: b:
      let
        a = coerce b a_;
      in
        if a ? ipv6
        then {
          ipv6 = {
            a = bit.and a.ipv6.a b.ipv6.a;
            b = bit.and a.ipv6.b b.ipv6.b;
            c = bit.and a.ipv6.c b.ipv6.c;
            d = bit.and a.ipv6.d b.ipv6.d;
          };
        }
        else if a ? ipv4
        then {
          ipv4 = bit.and a.ipv4 b.ipv4;
        }
        else if a ? mac
        then {
          mac = bit.and a.mac b.mac;
        }
        else bit.and a b;

    # not :: (ip | mac | integer) -> (ip | mac | integer)
    not = a:
      if a ? ipv6
      then {
        ipv6 = {
          a = bit.mask 32 (bit.not a.ipv6.a);
          b = bit.mask 32 (bit.not a.ipv6.b);
          c = bit.mask 32 (bit.not a.ipv6.c);
          d = bit.mask 32 (bit.not a.ipv6.d);
        };
      }
      else if a ? ipv4
      then {
        ipv4 = bit.mask 32 (bit.not a.ipv4);
      }
      else if a ? mac
      then {
        mac = bit.mask 48 (bit.not a.mac);
      }
      else bit.not a;

    # add :: (ip | mac | integer) -> (ip | mac | integer) -> (ip | mac | integer)
    add =
      let
        split = a: {
          fst = bit.mask 32 (bit.right 32 a);
          snd = bit.mask 32 a;
        };
      in
        a_: b:
          let
            a = coerce b a_;
          in
            if a ? ipv6
            then
              let
                a' = split (a.ipv6.a + b.ipv6.a + b'.fst);
                b' = split (a.ipv6.b + b.ipv6.b + c'.fst);
                c' = split (a.ipv6.c + b.ipv6.c + d'.fst);
                d' = split (a.ipv6.d + b.ipv6.d);
              in
                {
                  ipv6 = {
                    a = a'.snd;
                    b = b'.snd;
                    c = c'.snd;
                    d = d'.snd;
                  };
                }
            else if a ? ipv4
            then {
              ipv4 = bit.mask 32 (a.ipv4 + b.ipv4);
            }
            else if a ? mac
            then {
              mac = bit.mask 48 (a.mac + b.mac);
            }
            else a + b;

    # subtract :: (ip | mac | integer) -> (ip | mac | integer) -> (ip | mac | integer)
    subtract = a: b: add (add 1 (not (coerce b a))) b;

    # diff :: (ip | mac | integer) -> (ip | mac | integer) -> (ipv6 | integer)
    diff = a: b:
      let
        toIPv6 = coerce ({ ipv6.a = 0; });
        result = (subtract b (toIPv6 a)).ipv6;
        max32 = bit.left 32 1 - 1;
      in
        if result.a == 0 && result.b == 0 && bit.right 31 result.c == 0 || result.a == max32 && result.b == max32 && bit.right 31 result.c == 1
        then bit.or (bit.left 32 result.c) result.d
        else {
          ipv6 = result;
        };

    # left :: integer -> (ip | mac | integer) -> (ip | mac | integer)
    left = i: right (-i);

    # right :: integer -> (ip | mac | integer) -> (ip | mac | integer)
    right =
      let
        step = i: x: {
          _1 = bit.mask 32 (bit.right (i + 96) x);
          _2 = bit.mask 32 (bit.right (i + 64) x);
          _3 = bit.mask 32 (bit.right (i + 32) x);
          _4 = bit.mask 32 (bit.right i x);
          _5 = bit.mask 32 (bit.right (i - 32) x);
          _6 = bit.mask 32 (bit.right (i - 64) x);
          _7 = bit.mask 32 (bit.right (i - 96) x);
        };
        ors = builtins.foldl' bit.or 0;
      in
        i: x:
          if x ? ipv6
          then
            let
              a' = step i x.ipv6.a;
              b' = step i x.ipv6.b;
              c' = step i x.ipv6.c;
              d' = step i x.ipv6.d;
            in
              {
                ipv6 = {
                  a = ors [ a'._4 b'._3 c'._2 d'._1 ];
                  b = ors [ a'._5 b'._4 c'._3 d'._2 ];
                  c = ors [ a'._6 b'._5 c'._4 d'._3 ];
                  d = ors [ a'._7 b'._6 c'._5 d'._4 ];
                };
              }
          else if x ? ipv4
          then {
            ipv4 = bit.mask 32 (bit.right i x.ipv4);
          }
          else if x ? mac
          then {
            mac = bit.mask 48 (bit.right i x.mac);
          }
          else bit.right i x;

    # shadow :: integer -> (ip | mac | integer) -> (ip | mac | integer)
    shadow = n: a: and (right n (left n (coerce a (-1)))) a;

    # coshadow :: integer -> (ip | mac | integer) -> (ip | mac | integer)
    coshadow = n: a: and (not (right n (left n (coerce a (-1))))) a;

    # coerce :: (ip | mac | integer) -> (ip | mac | integer) -> (ip | mac | integer)
    coerce = target: value:
      if target ? ipv6
      then
        if value ? ipv6
        then value
        else if value ? ipv4
        then {
          ipv6 = {
            a = 0;
            b = 0;
            c = 0;
            d = value.ipv4;
          };
        }
        else if value ? mac
        then {
          ipv6 = {
            a = 0;
            b = 0;
            c = bit.right 32 value.mac;
            d = bit.mask 32 value.mac;
          };
        }
        else {
          ipv6 = {
            a = bit.mask 32 (bit.right 96 value);
            b = bit.mask 32 (bit.right 64 value);
            c = bit.mask 32 (bit.right 32 value);
            d = bit.mask 32 value;
          };
        }
      else if target ? ipv4
      then
        if value ? ipv6
        then {
          ipv4 = value.ipv6.d;
        }
        else if value ? ipv4
        then value
        else if value ? mac
        then {
          ipv4 = bit.mask 32 value.mac;
        }
        else {
          ipv4 = bit.mask 32 value;
        }
      else if target ? mac
      then
        if value ? ipv6
        then {
          mac = bit.or (bit.left 32 (bit.mask 16 value.ipv6.c)) value.ipv6.d;
        }
        else if value ? ipv4
        then {
          mac = value.ipv4;
        }
        else if value ? mac
        then value
        else {
          mac = bit.mask 48 value;
        }
      else
        if value ? ipv6
        then builtins.foldl' bit.or 0
          [
            (bit.left 96 value.ipv6.a)
            (bit.left 64 value.ipv6.b)
            (bit.left 32 value.ipv6.c)
            value.ipv6.d
          ]
        else if value ? ipv4
        then value.ipv4
        else if value ? mac
        then value.mac
        else value;
  };

  implementations = {
    ip = {
      # add :: (ip | mac | integer) -> ip -> ip
      add = arithmetic.add;

      # diff :: ip -> ip -> (ipv6 | integer)
      diff = arithmetic.diff;

      # subtract :: (ip | mac | integer) -> ip -> ip
      subtract = arithmetic.subtract;
    };

    mac = {
      # add :: (ip | mac | integer) -> mac -> mac
      add = arithmetic.add;

      # diff :: mac -> mac -> (ipv6 | integer)
      diff = arithmetic.diff;

      # subtract :: (ip | mac | integer) -> mac -> mac
      subtract = arithmetic.subtract;
    };

    cidr = rec {
      # add :: (ip | mac | integer) -> cidr -> cidr
      add = delta: cidr:
        let
          size' = size cidr;
        in
          {
            base = arithmetic.left size' (arithmetic.add delta (arithmetic.right size' cidr.base));
            inherit (cidr) length;
          };

      # capacity :: cidr -> integer
      capacity = cidr:
        let
          size' = size cidr;
        in
          if size' > 62
          then 9223372036854775807 # maxBound to prevent overflow
          else bit.left size' 1;

      # child :: cidr -> cidr -> bool
      child = subcidr: cidr:
        length subcidr > length cidr && contains (host 0 subcidr) cidr;

      # contains :: ip -> cidr -> bool
      contains = ip: cidr: host 0 (make cidr.length ip) == host 0 cidr;

      # host :: (ip | mac | integer) -> cidr -> ip
      host = index: cidr:
        let
          index' = arithmetic.coerce cidr.base index;
        in
          arithmetic.or (arithmetic.shadow cidr.length index') cidr.base;

      # length :: cidr -> integer
      length = cidr: cidr.length;

      # netmask :: cidr -> ip
      netmask = cidr: arithmetic.coshadow cidr.length (arithmetic.coerce cidr.base (-1));

      # size :: cidr -> integer
      size = cidr: (if cidr.base ? ipv6 then 128 else 32) - cidr.length;

      # subnet :: integer -> (ip | mac | integer) -> cidr -> cidr
      subnet = length: index: cidr:
        let
          length' = cidr.length + length;
          index' = arithmetic.coerce cidr.base index;
          size = (if cidr.base ? ipv6 then 128 else 32) - length';
        in
          make length' (host (arithmetic.left size index') cidr);

      # make :: integer -> ip -> cidr
      make = length: base:
        let
          length' = math.clamp 0 (if base ? ipv6 then 128 else 32) length;
        in
          {
            base = arithmetic.coshadow length' base;
            length = length';
          };
    };
  };

  typechecks =
    let

      fail = description: function: argument:
        builtins.throw "${function}: ${argument} parameter must be ${description}";

      meta = parser: description: function: argument: input:
        let
          error = fail description function argument;
        in
          if !builtins.isString input
          then error
          else
            let
              result = parser input;
            in
              if builtins.isNull result
              then error
              else result;

    in
      {
        int = function: argument: input:
          if builtins.isInt input
          then input
          else fail "an integer" function argument;
        ip = meta parsers.ip "an IPv4 or IPv6 address";
        cidr = meta parsers.cidr "an IPv4 or IPv6 address range in CIDR notation";
        mac = meta parsers.mac "a MAC address";
        numeric = function: argument: input:
          if builtins.isInt input
          then input
          else meta parsers.numeric "an integer or IPv4, IPv6 or MAC address" function argument input;
      };

in net
