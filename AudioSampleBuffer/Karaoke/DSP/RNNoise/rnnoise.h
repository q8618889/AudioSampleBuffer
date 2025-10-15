/* Copyright (c) 2018 Mozilla
                  2008-2011 Octasic Inc.
                  2012-2017 Jean-Marc Valin */
/*
   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

   - Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.
*/

#ifndef RNNOISE_H
#define RNNOISE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef struct DenoiseState DenoiseState;

/**
 * Return the size of DenoiseState
 */
int rnnoise_get_size(void);

/**
 * Return the number of samples processed by rnnoise_process_frame at a time
 */
int rnnoise_get_frame_size(void);

/**
 * Initialize a pre-allocated DenoiseState
 *
 * If model is NULL the default model is used.
 *
 * See: rnnoise_create() and rnnoise_get_size()
 */
DenoiseState *rnnoise_init(DenoiseState *st, void *model);

/**
 * Allocate and initialize a DenoiseState
 *
 * If model is NULL the default model is used.
 *
 * The returned pointer MUST be freed with rnnoise_destroy().
 */
DenoiseState *rnnoise_create(void *model);

/**
 * Free a DenoiseState produced by rnnoise_create.
 *
 * The optional custom model must be freed by the caller if applicable.
 */
void rnnoise_destroy(DenoiseState *st);

/**
 * Denoise a frame of samples
 *
 * @param st      DenoiseState
 * @param x       [in,out] input/output audio samples (size: rnnoise_get_frame_size())
 *
 * @returns probability of voice activity (0.0 - 1.0)
 */
float rnnoise_process_frame(DenoiseState *st, float *x);

#ifdef __cplusplus
}
#endif

#endif

