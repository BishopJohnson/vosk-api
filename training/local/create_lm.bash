#!/usr/bin/env bash

# Code snippet from Kaldi for Dummies tutorial.
#
# Credits: kaldi-asr https://kaldi-asr.org/doc/kaldi_for_dummies.html#kaldi_for_dummies_running

lm_order=1 # Language model order (n-gram quantity) - Value of 1 is enough for digits grammar.

# Remove data from previous run
rm -rf data/local/tmp

loc=$(which ngram-count);

if [ -z "$loc" ]; then
  if uname -a | grep 64 > /dev/null; then
    sdir=$KALDI_ROOT/tools/srilm/bin/i686-m64
  else
    sdir=$KALDI_ROOT/tools/srilm/bin/i686-
  fi
  
  if [ -f "$sdir"/ngram-count ]; then
    echo "Using SRILM language modelling tool from $sdir"
    export PATH=$PATH:$sdir
  else
    echo "SRILM toolkit is probably not installed. Instructions: tools/install_srilm.sh"
    exit 1
  fi
fi

local=data/local
mkdir $local/tmp
ngram-count -order $lm_order -write-vocab $local/tmp/vocab-full.txt -wbdiscount -text $local/corpus.txt -lm $local/tmp/lm.arpa