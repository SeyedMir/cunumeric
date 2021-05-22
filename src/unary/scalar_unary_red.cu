/* Copyright 2021 NVIDIA Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#include "unary/scalar_unary_red.h"
#include "unary/scalar_unary_red_template.inl"

namespace legate {
namespace numpy {

using namespace Legion;

template <typename Op,
          typename Output,
          typename ReadAcc,
          typename Pitches,
          typename Point,
          typename VAL>
static __global__ void __launch_bounds__(THREADS_PER_BLOCK, MIN_CTAS_PER_SM)
  reduction_kernel(size_t volume,
                   Op op,
                   Output out,
                   ReadAcc in,
                   Pitches pitches,
                   Point origin,
                   size_t iters,
                   VAL identity)
{
  auto value = identity;
  for (size_t idx = 0; idx < iters; idx++) {
    const size_t offset = (idx * gridDim.x + blockIdx.x) * blockDim.x + threadIdx.x;
    if (offset < volume) {
      auto point = pitches.unflatten(offset, origin);
      Op::template fold<true>(value, in[point]);
    }
  }
  // Every thread in the thread block must participate in the exchange to get correct results
  reduce_output(out, value);
}

template <UnaryRedCode OP_CODE, LegateTypeCode CODE, int DIM>
struct ScalarUnaryRedImplBody<VariantKind::GPU, OP_CODE, CODE, DIM> {
  using OP  = UnaryRedOp<OP_CODE, CODE>;
  using VAL = legate_type_of<CODE>;

  void operator()(OP func,
                  VAL &result,
                  AccessorRO<VAL, DIM> in,
                  const Rect<DIM> &rect,
                  const Pitches<DIM - 1> &pitches,
                  bool dense) const
  {
    cudaStream_t stream;
    cudaStreamCreate(&stream);

    const size_t volume = rect.volume();
    const size_t blocks = (volume + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;
    DeferredReduction<typename OP::OP> out;
    size_t shmem_size = THREADS_PER_BLOCK / 32 * sizeof(VAL);

    if (blocks >= MAX_REDUCTION_CTAS) {
      const size_t iters = (blocks + MAX_REDUCTION_CTAS - 1) / MAX_REDUCTION_CTAS;
      reduction_kernel<<<MAX_REDUCTION_CTAS, THREADS_PER_BLOCK, shmem_size, stream>>>(
        volume, typename OP::OP{}, out, in, pitches, rect.lo, iters, OP::identity);
    } else
      reduction_kernel<<<blocks, THREADS_PER_BLOCK, shmem_size, stream>>>(
        volume, typename OP::OP{}, out, in, pitches, rect.lo, 1, OP::identity);

    // TODO: We eventually want to unblock this step
    cudaStreamSynchronize(stream);
    cudaStreamDestroy(stream);

    result = out.read();
  }
};

/*static*/ UntypedScalar ScalarUnaryRedTask::gpu_variant(const Task *task,
                                                         const std::vector<PhysicalRegion> &regions,
                                                         Context context,
                                                         Runtime *runtime)
{
  return scalar_unary_red_template<VariantKind::GPU>(task, regions, context, runtime);
}

}  // namespace numpy
}  // namespace legate