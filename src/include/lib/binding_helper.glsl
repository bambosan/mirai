#ifndef BINDING_HELPER_INCLUDED
#define BINDING_HELPER_INCLUDED

//_REG macro expansion supplied by Lazurite, so there is no need to set bindings manually

#define SAMPLER2D(_name) \
    layout(binding = _name ## _REG) uniform sampler2D _name
#define SAMPLER3D(_name) \
    layout(binding = _name ## _REG) uniform sampler3D _name
#define SAMPLERCUBE(_name) \
    layout(binding = _name ## _REG) uniform samplerCube _name
#define SAMPLER2DSHADOW(_name) \
    layout(binding = _name ## _REG) uniform sampler2DShadow _name
#define SAMPLER2DARRAY(_name) \
    layout(binding = _name ## _REG) uniform sampler2DArray _name
#define SAMPLERCUBEARRAY(_name) \
    layout(binding = _name ## _REG) uniform samplerCubeArray _name
#define SAMPLERCUBEARRAYSHADOW(_name) \
    layout(binding = _name ## _REG) uniform samplerCubeArrayShadow _name
#define SAMPLER2DARRAYSHADOW(_name) \
    layout(binding = _name ## _REG) uniform sampler2DArrayShadow _name
#define ISAMPLER2D(_name) \
    layout(binding = _name ## _REG) uniform isampler2D _name
#define USAMPLER2D(_name) \
    layout(binding = _name ## _REG) uniform usampler2D _name
#define ISAMPLER3D(_name) \
    layout(binding = _name ## _REG) uniform isampler3D _name
#define USAMPLER3D(_name) \
    layout(binding = _name ## _REG) uniform usampler3D _name

#define IMAGE2D_RO(_name, _format) \
    layout(binding = _name ## _REG, _format) readonly uniform image2D _name
#define UIMAGE2D_RO(_name, _format) \
    layout(binding = _name ## _REG, _format) readonly uniform uimage2D _name
#define IMAGE2D_WO(_name, _format) \
    layout(binding = _name ## _REG, _format) writeonly uniform image2D _name
#define UIMAGE2D_WO(_name, _format) \
    layout(binding = _name ## _REG, _format) writeonly uniform uimage2D _name
#define IMAGE2D_RW(_name, _format) \
    layout(binding = _name ## _REG, _format) uniform image2D _name
#define UIMAGE2D_RW(_name, _format) \
    layout(binding = _name ## _REG, _format) uniform uimage2D _name
#define IMAGE2D_ARRAY_RO(_name, _format) \
    layout(binding = _name ## _REG, _format) readonly uniform image2DArray _name
#define UIMAGE2D_ARRAY_RO(_name, _format) \
    layout(binding = _name ## _REG, _format) readonly uniform uimage2DArray _name
#define IMAGE2D_ARRAY_WO(_name, _format) \
    layout(binding = _name ## _REG, _format) writeonly uniform image2DArray _name
#define UIMAGE2D_ARRAY_WO(_name, _format) \
    layout(binding = _name ## _REG, _format) writeonly uniform uimage2DArray _name
#define IMAGE2D_ARRAY_RW(_name, _format) \
    layout(binding = _name ## _REG, _format) uniform image2DArray _name
#define UIMAGE2D_ARRAY_RW(_name, _format) \
    layout(binding = _name ## _REG, _format) uniform uimage2DArray _name
#define IMAGE3D_RO(_name, _format) \
    layout(binding = _name ## _REG, _format) readonly uniform image3D _name
#define UIMAGE3D_RO(_name, _format) \
    layout(binding = _name ## _REG, _format) readonly uniform uimage3D _name
#define IMAGE3D_WO(_name, _format) \
    layout(binding = _name ## _REG, _format) writeonly uniform image3D _name
#define UIMAGE3D_WO(_name, _format) \
    layout(binding = _name ## _REG, _format) writeonly uniform uimage3D _name
#define IMAGE3D_RW(_name, _format) \
    layout(binding = _name ## _REG, _format) uniform image3D _name
#define UIMAGE3D_RW(_name, _format) \
    layout(binding = _name ## _REG, _format) uniform uimage3D _name

#define BUFFER_RO(_name, _type, _instance) \
    layout(std430, binding = _name ## _REG) readonly buffer _name { \
        _type _data[]; \
    } _instance
#define BUFFER_WO(_name, _type, _instance) \
    layout(std430, binding = _name ## _REG) writeonly buffer _name { \
        _type _data[]; \
    } _instance
#define BUFFER_RW(_name, _type, _instance) \
    layout(std430, binding = _name ## _REG) buffer _name { \
        _type _data[]; \
    } _instance

#endif
