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

namespace legate {
namespace numpy {

using namespace Legion;

template <VariantKind KIND, typename VAL>
struct WriteImplBody;

template <VariantKind KIND>
struct WriteImpl {
  template <LegateTypeCode CODE>
  void operator()(Array& out_arr, Array& in_arr) const
  {
    using VAL = legate_type_of<CODE>;
    auto out  = out_arr.write_accessor<VAL, 1>();
    auto in   = in_arr.read_accessor<VAL, 1>();
    WriteImplBody<KIND, VAL>()(out, in);
  }
};

template <VariantKind KIND>
static void write_template(TaskContext& context)
{
  auto& in  = context.inputs()[0];
  auto& out = context.outputs()[0];
  type_dispatch(out.code(), WriteImpl<KIND>{}, out, in);
}

}  // namespace numpy
}  // namespace legate