# wikidata-tools
Fast and simple tooling for Wikidata N-Triples.

## Setup

Requirements:
* Groovy for fetching the Wikidata release state. Easy install using [SDKMAN](https://sdkman.io/): `sdk install groovy`.
* NQPatch for creating patching between sorted N-Quads files: https://github.com/Scaseco/nqpatch-posix - clone the repo and make `nqpatch` available on the PATH.

```bash
chmod +x wikidata-release-status.groovy
```

## Fetch release status in JSON

```bash
./wikidata-release-status.groovy
```

```json
{
  "truthy-BETA": [
    {
      "date": 20250625,
      "url": "https://dumps.wikimedia.org/wikidatawiki/entities/20250625/wikidata-20250625-truthy-BETA.nt.bz2"
    }
  ],
  "lexemes-BETA": [
    {
      "date": 20250627,
      "url": "https://dumps.wikimedia.org/wikidatawiki/entities/20250627/wikidata-20250627-lexemes-BETA.nt.bz2"
    }
  ]
}
```

Latest release is at array index 0.

### Custom base URL (for testing)

To test against a local repository, specify a custom base URL as the first argument:

```bash
./wikidata-release-status.groovy http://localhost/~the_user/wikidata/test-repo/
```

This is useful when using e.g. Apache with userdir to serve a local test repository.

Options can be specified after the base URL:

```bash
./wikidata-release-status.groovy http://localhost/~the_user/wikidata/test-repo/ --since 20250601
```

Use `jq` for post processing, such as:

```bash
./wikidata-release-status.groovy | jq -r '."truthy-BETA"[0].url'

https://dumps.wikimedia.org/wikidatawiki/entities/20250625/wikidata-20250625-truthy-BETA.nt.bz2
```

## Sort

* `LC_ALL=C` is important to sort by the raw bytes - independent of your locale.
* Adjust memory to your needs.

```bash
lbzcat wikidata-20250618-truthy-BETA.nt.bz2 | LC_ALL=C sort -u -S 80g | lbzip2 -cz > wikidata-20250618-truthy-BETA.sorted.nt.bz2
```

## Fast Diffs from Sorted Data
Uncompressed wikidata is ~1TB. Running from compressed files works on conventional hardware.

This script uses bash process substitution `<(...)` to stream compressed data.
```bash
LC_ALL=C comm -23 <(lbzcat wikidata-20250606-truthy-BETA.sorted.nt.bz2) <(lbzcat wikidata-20250530-truthy-BETA.sorted.nt.bz2) | lbzip2 -cz > added.nt.bz2
LC_ALL=C comm -13 <(lbzcat wikidata-20250606-truthy-BETA.sorted.nt.bz2) <(lbzcat wikidata-20250530-truthy-BETA.sorted.nt.bz2) | lbzip2 -cz > removed.nt.bz2
```

You can use the diffs to patch data in your SPARQL endpoint.
A single diff file (only added OR removed) seems to be roughly ~15M triples - a Wikidata truthy dump is 8000M triples.

