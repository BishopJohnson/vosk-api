#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh

stage=-1
stop_stage=100
dynamic_graph=false

. utils/parse_options.sh

# Data preparation
if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
  local/data_prep.sh corpus/audio/train-clean data/train
  local/data_prep.sh corpus/audio/test-clean data/test
fi

# Dictionary formatting
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
  local/prepare_dict.sh data/local/lm data/local/dict
  utils/prepare_lang.sh data/local/dict "<UNK>" data/local/lang data/lang
fi

# Extract MFCC features
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
  for task in train; do
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 10 data/$task exp/make_mfcc/$task $mfcc
    steps/compute_cmvn_stats.sh data/$task exp/make_mfcc/$task $mfcc
  done
fi

# Train GMM models
if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
  steps/train_mono.sh --nj 10 --cmd "$train_cmd" \
    data/train data/lang exp/mono

  steps/align_si.sh  --nj 10 --cmd "$train_cmd" \
    data/train data/lang exp/mono exp/mono_ali

  steps/train_lda_mllt.sh  --cmd "$train_cmd" \
    2000 10000 data/train data/lang exp/mono_ali exp/tri1

  steps/align_si.sh --nj 10 --cmd "$train_cmd" \
    data/train data/lang exp/tri1 exp/tri1_ali

  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    2500 15000 data/train data/lang exp/tri1_ali exp/tri2

  steps/align_si.sh  --nj 10 --cmd "$train_cmd" \
    data/train data/lang exp/tri2 exp/tri2_ali

  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    2500 20000 data/train data/lang exp/tri2_ali exp/tri3

  steps/align_si.sh  --nj 10 --cmd "$train_cmd" \
    data/train data/lang exp/tri3 exp/tri3_ali
fi

# Train TDNN model
if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ]; then
  local/chain/run_tdnn.sh
fi

# Decode
if [ ${stage} -le 5 ] && [ ${stop_stage} -ge 5 ]; then
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${KALDI_ROOT}/tools/openfst/lib/fst

  utils/format_lm.sh data/lang data/local/lm/lm.arpa.gz data/local/lm/vocab-full.txt data/lang_test

  if [ ${dynamic_graph} = true ]; then
    utils/mkgraph_lookahead.sh --self-loop-scale 1.0 data/lang_test exp/chain/tdnn exp/chain/tdnn/graph
  else
    utils/mkgraph.sh --self-loop-scale 1.0 data/lang_test exp/chain/tdnn exp/chain/tdnn/graph
  fi

  utils/build_const_arpa_lm.sh data/local/lm/lm.arpa.gz data/lang data/lang_test_rescore

  for task in test; do
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 10 data/$task exp/make_mfcc/$task $mfcc
    steps/compute_cmvn_stats.sh data/$task exp/make_mfcc/$task $mfcc

    steps/online/nnet2/extract_ivectors_online.sh --nj 10 \
        data/${task} exp/chain/extractor \
        exp/chain/ivectors_${task}

    if [ ${dynamic_graph} = true ]; then
      steps/nnet3/decode_lookahead.sh --cmd $decode_cmd \
        --nj 1 \
        --beam 13.0 \
        --max-active 7000 \
        --lattice-beam 4.0 \
        --online-ivector-dir exp/chain/ivectors_${task} \
        --acwt 1.0 \
        --post-decode-acwt 10.0 \
        --use-gpu true \
        exp/chain/tdnn/graph data/${task} exp/chain/tdnn/decode_${task}
      else
        steps/nnet3/decode.sh --cmd $decode_cmd \
              --num-threads 10 \
              --nj 1 \
              --beam 13.0 \
              --max-active 7000 \
              --lattice-beam 4.0 \
              --online-ivector-dir exp/chain/ivectors_${task} \
              --acwt 1.0 \
              --post-decode-acwt 10.0 \
              --use-gpu true \
              exp/chain/tdnn/graph data/${task} exp/chain/tdnn/decode_${task}
      fi
  done
fi

# Test
if [ ${stage} -le 6 ] && [ ${stop_stage} -ge 6 ]; then
  for task in test; do
    steps/lmrescore_const_arpa.sh data/lang_test data/lang_test_rescore \
            data/${task} exp/chain/tdnn/decode_${task} exp/chain/tdnn/decode_${task}_rescore
  done
  
  bash RESULTS
fi
