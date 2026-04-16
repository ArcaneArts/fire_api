// GENERATED – do not modify by hand

// ignore_for_file: camel_case_types
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: constant_identifier_names
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: unused_element
import "package:fire_api/fire_api.dart";import "package:artifact/artifact.dart";import "dart:core";
typedef _0=ArtifactCodecUtil;typedef _1=ArtifactDataUtil;typedef _2=ArtifactSecurityUtil;typedef _3=ArtifactReflection;typedef _4=ArtifactMirror;typedef _5=Map<String,dynamic>;typedef _6=List<String>;typedef _7=String;typedef _8=dynamic;typedef _9=int;typedef _a=ArtifactModelExporter;typedef _b=ArgumentError;typedef _c=Exception;typedef _d=VectorValue;typedef _e=ArtifactModelImporter<VectorValue>;typedef _f=double;typedef _g=List;typedef _h=bool;typedef _i=List<double>;typedef _j=ArtifactAccessor;typedef _k=List<dynamic>;
_b __x(_7 c,_7 f)=>_b('${_S[3]}$c.$f');
const _6 _S=['magic\$type','vector','fire_api','Missing required '];const _k _V=[vectorValueMagicTypeValue,<_f>[]];const _h _T=true;const _h _F=false;_9 _ = ((){if(!_j.$i(_S[2])){_j.$r(_S[2],_j(isArtifact: $isArtifact,artifactMirror:{},constructArtifact:$constructArtifact,artifactToMap:$artifactToMap,artifactFromMap:$artifactFromMap));}return 0;})();

extension $VectorValue on _d{
  _d get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(magic$type),_S[1]:vector.$m((e)=> _0.ea(e)).$l,}.$nn;}
  static _e get from=>_e(fromMap);
  static _d fromMap(_5 r){_;_5 m=r.$nn;return _d(magic$type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[0],vector: m.$c(_S[1]) ?  (m[_S[1]] as _g).$m((e)=> _0.da(e, _f) as _f).$l : _V[1],);}
  _d copyWith({_7? magic$type,_h resetMagic$type=_F,_i? vector,_h resetVector=_F,_i? appendVector,_i? removeVector,})=>_d(magic$type: resetMagic$type?_V[0]:(magic$type??_H.magic$type),vector: ((resetVector?_V[1]:(vector??_H.vector)) as _i).$u(appendVector,removeVector),);
  static _d get newInstance=>_d();
}

bool $isArtifact(dynamic v)=>v==null?false : v is! Type ?$isArtifact(v.runtimeType):v == _d ;
T $constructArtifact<T>() => T==_d ?$VectorValue.newInstance as T : throw _c();
_5 $artifactToMap(Object o)=>o is _d ?o.toMap():throw _c();
T $artifactFromMap<T>(_5 m)=>T==_d ?$VectorValue.fromMap(m) as T:throw _c();
