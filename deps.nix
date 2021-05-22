{ lib, beamPackages, overrides ? (x: y: {}) }:

let
	buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;
	buildMix = lib.makeOverridable beamPackages.buildMix;
	buildErlangMk = lib.makeOverridable beamPackages.buildErlangMk;

	self = packages // (overrides self packages);

	packages = with beamPackages; with self; {
		castore = buildMix rec {
			name = "castore";
			version = "0.1.10";

			src = fetchHex {
				pkg = "${name}";
				version = "${version}";
				sha256 = "0r96zwva2g6q59vyar8swaka0vxx27xfpf17xar2ss25rgh190x4";
			};

			beamDeps = [];
		};

		jason = buildMix rec {
			name = "jason";
			version = "1.2.2";

			src = fetchHex {
				pkg = "${name}";
				version = "${version}";
				sha256 = "0y91s7q8zlfqd037c1mhqdhrvrf60l4ax7lzya1y33h5y3sji8hq";
			};

			beamDeps = [];
		};

		matrix_sdk = buildMix rec {
			name = "matrix_sdk";
			version = "0.2.0";

			src = fetchHex {
				pkg = "${name}";
				version = "${version}";
				sha256 = "06lhfs9rwjw84gf0y9fzz88akpn2s3wf9x67jlarfwk82s2z4xl8";
			};

			beamDeps = [ castore jason mint tesla ];
		};

		mime = buildMix rec {
			name = "mime";
			version = "1.6.0";

			src = fetchHex {
				pkg = "${name}";
				version = "${version}";
				sha256 = "19qrpnmaf3w8bblvkv6z5g82hzd10rhc7bqxvqyi88c37xhsi89i";
			};

			beamDeps = [];
		};

		mint = buildMix rec {
			name = "mint";
			version = "1.3.0";

			src = fetchHex {
				pkg = "${name}";
				version = "${version}";
				sha256 = "07jw3l9v0jpvshym9iffk21qp9xzd9bpclbylxlwlhrfarhckam9";
			};

			beamDeps = [ castore ];
		};

		tesla = buildMix rec {
			name = "tesla";
			version = "1.4.1";

			src = fetchHex {
				pkg = "${name}";
				version = "${version}";
				sha256 = "06i0rshkm1byzgsphbr3al4hns7bcrpl1rxy8lwlp31cj8sxxxcm";
			};

			beamDeps = [ castore jason mime mint ];
		};

		uuid = buildMix rec {
			name = "uuid";
			version = "1.1.8";

			src = fetchHex {
				pkg = "${name}";
				version = "${version}";
				sha256 = "1b7jjbkmp42rayl6nif6qirksnxgxzksm2rpq9fiyq1v9hxmk467";
			};

			beamDeps = [];
		};
	};
in self

