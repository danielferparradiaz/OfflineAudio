// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'events.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Event {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Event);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Event()';
}


}

/// @nodoc
class $EventCopyWith<$Res>  {
$EventCopyWith(Event _, $Res Function(Event) __);
}


/// Adds pattern-matching-related methods to [Event].
extension EventPatterns on Event {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Event_DownloadProgress value)?  downloadProgress,TResult Function( Event_DownloadFinished value)?  downloadFinished,TResult Function( Event_DownloadFailed value)?  downloadFailed,TResult Function( Event_DownloadCancelled value)?  downloadCancelled,TResult Function( Event_DownloadSkippedDuplicate value)?  downloadSkippedDuplicate,TResult Function( Event_YtdlpStatus value)?  ytdlpStatus,TResult Function( Event_Notify value)?  notify,TResult Function( Event_LibraryChanged value)?  libraryChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Event_DownloadProgress() when downloadProgress != null:
return downloadProgress(_that);case Event_DownloadFinished() when downloadFinished != null:
return downloadFinished(_that);case Event_DownloadFailed() when downloadFailed != null:
return downloadFailed(_that);case Event_DownloadCancelled() when downloadCancelled != null:
return downloadCancelled(_that);case Event_DownloadSkippedDuplicate() when downloadSkippedDuplicate != null:
return downloadSkippedDuplicate(_that);case Event_YtdlpStatus() when ytdlpStatus != null:
return ytdlpStatus(_that);case Event_Notify() when notify != null:
return notify(_that);case Event_LibraryChanged() when libraryChanged != null:
return libraryChanged(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Event_DownloadProgress value)  downloadProgress,required TResult Function( Event_DownloadFinished value)  downloadFinished,required TResult Function( Event_DownloadFailed value)  downloadFailed,required TResult Function( Event_DownloadCancelled value)  downloadCancelled,required TResult Function( Event_DownloadSkippedDuplicate value)  downloadSkippedDuplicate,required TResult Function( Event_YtdlpStatus value)  ytdlpStatus,required TResult Function( Event_Notify value)  notify,required TResult Function( Event_LibraryChanged value)  libraryChanged,}){
final _that = this;
switch (_that) {
case Event_DownloadProgress():
return downloadProgress(_that);case Event_DownloadFinished():
return downloadFinished(_that);case Event_DownloadFailed():
return downloadFailed(_that);case Event_DownloadCancelled():
return downloadCancelled(_that);case Event_DownloadSkippedDuplicate():
return downloadSkippedDuplicate(_that);case Event_YtdlpStatus():
return ytdlpStatus(_that);case Event_Notify():
return notify(_that);case Event_LibraryChanged():
return libraryChanged(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Event_DownloadProgress value)?  downloadProgress,TResult? Function( Event_DownloadFinished value)?  downloadFinished,TResult? Function( Event_DownloadFailed value)?  downloadFailed,TResult? Function( Event_DownloadCancelled value)?  downloadCancelled,TResult? Function( Event_DownloadSkippedDuplicate value)?  downloadSkippedDuplicate,TResult? Function( Event_YtdlpStatus value)?  ytdlpStatus,TResult? Function( Event_Notify value)?  notify,TResult? Function( Event_LibraryChanged value)?  libraryChanged,}){
final _that = this;
switch (_that) {
case Event_DownloadProgress() when downloadProgress != null:
return downloadProgress(_that);case Event_DownloadFinished() when downloadFinished != null:
return downloadFinished(_that);case Event_DownloadFailed() when downloadFailed != null:
return downloadFailed(_that);case Event_DownloadCancelled() when downloadCancelled != null:
return downloadCancelled(_that);case Event_DownloadSkippedDuplicate() when downloadSkippedDuplicate != null:
return downloadSkippedDuplicate(_that);case Event_YtdlpStatus() when ytdlpStatus != null:
return ytdlpStatus(_that);case Event_Notify() when notify != null:
return notify(_that);case Event_LibraryChanged() when libraryChanged != null:
return libraryChanged(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String taskId,  double percent,  BigInt downloadedBytes,  BigInt? totalBytes,  BigInt? speedBytesSec,  BigInt? etaSecs)?  downloadProgress,TResult Function( String taskId,  Track track)?  downloadFinished,TResult Function( String taskId,  String reason)?  downloadFailed,TResult Function( String taskId)?  downloadCancelled,TResult Function( String taskId,  Track track)?  downloadSkippedDuplicate,TResult Function( bool present,  String? version,  bool outdated,  String? lastChecked,  String? message)?  ytdlpStatus,TResult Function( String kind,  String message)?  notify,TResult Function()?  libraryChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Event_DownloadProgress() when downloadProgress != null:
return downloadProgress(_that.taskId,_that.percent,_that.downloadedBytes,_that.totalBytes,_that.speedBytesSec,_that.etaSecs);case Event_DownloadFinished() when downloadFinished != null:
return downloadFinished(_that.taskId,_that.track);case Event_DownloadFailed() when downloadFailed != null:
return downloadFailed(_that.taskId,_that.reason);case Event_DownloadCancelled() when downloadCancelled != null:
return downloadCancelled(_that.taskId);case Event_DownloadSkippedDuplicate() when downloadSkippedDuplicate != null:
return downloadSkippedDuplicate(_that.taskId,_that.track);case Event_YtdlpStatus() when ytdlpStatus != null:
return ytdlpStatus(_that.present,_that.version,_that.outdated,_that.lastChecked,_that.message);case Event_Notify() when notify != null:
return notify(_that.kind,_that.message);case Event_LibraryChanged() when libraryChanged != null:
return libraryChanged();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String taskId,  double percent,  BigInt downloadedBytes,  BigInt? totalBytes,  BigInt? speedBytesSec,  BigInt? etaSecs)  downloadProgress,required TResult Function( String taskId,  Track track)  downloadFinished,required TResult Function( String taskId,  String reason)  downloadFailed,required TResult Function( String taskId)  downloadCancelled,required TResult Function( String taskId,  Track track)  downloadSkippedDuplicate,required TResult Function( bool present,  String? version,  bool outdated,  String? lastChecked,  String? message)  ytdlpStatus,required TResult Function( String kind,  String message)  notify,required TResult Function()  libraryChanged,}) {final _that = this;
switch (_that) {
case Event_DownloadProgress():
return downloadProgress(_that.taskId,_that.percent,_that.downloadedBytes,_that.totalBytes,_that.speedBytesSec,_that.etaSecs);case Event_DownloadFinished():
return downloadFinished(_that.taskId,_that.track);case Event_DownloadFailed():
return downloadFailed(_that.taskId,_that.reason);case Event_DownloadCancelled():
return downloadCancelled(_that.taskId);case Event_DownloadSkippedDuplicate():
return downloadSkippedDuplicate(_that.taskId,_that.track);case Event_YtdlpStatus():
return ytdlpStatus(_that.present,_that.version,_that.outdated,_that.lastChecked,_that.message);case Event_Notify():
return notify(_that.kind,_that.message);case Event_LibraryChanged():
return libraryChanged();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String taskId,  double percent,  BigInt downloadedBytes,  BigInt? totalBytes,  BigInt? speedBytesSec,  BigInt? etaSecs)?  downloadProgress,TResult? Function( String taskId,  Track track)?  downloadFinished,TResult? Function( String taskId,  String reason)?  downloadFailed,TResult? Function( String taskId)?  downloadCancelled,TResult? Function( String taskId,  Track track)?  downloadSkippedDuplicate,TResult? Function( bool present,  String? version,  bool outdated,  String? lastChecked,  String? message)?  ytdlpStatus,TResult? Function( String kind,  String message)?  notify,TResult? Function()?  libraryChanged,}) {final _that = this;
switch (_that) {
case Event_DownloadProgress() when downloadProgress != null:
return downloadProgress(_that.taskId,_that.percent,_that.downloadedBytes,_that.totalBytes,_that.speedBytesSec,_that.etaSecs);case Event_DownloadFinished() when downloadFinished != null:
return downloadFinished(_that.taskId,_that.track);case Event_DownloadFailed() when downloadFailed != null:
return downloadFailed(_that.taskId,_that.reason);case Event_DownloadCancelled() when downloadCancelled != null:
return downloadCancelled(_that.taskId);case Event_DownloadSkippedDuplicate() when downloadSkippedDuplicate != null:
return downloadSkippedDuplicate(_that.taskId,_that.track);case Event_YtdlpStatus() when ytdlpStatus != null:
return ytdlpStatus(_that.present,_that.version,_that.outdated,_that.lastChecked,_that.message);case Event_Notify() when notify != null:
return notify(_that.kind,_that.message);case Event_LibraryChanged() when libraryChanged != null:
return libraryChanged();case _:
  return null;

}
}

}

/// @nodoc


class Event_DownloadProgress extends Event {
  const Event_DownloadProgress({required this.taskId, required this.percent, required this.downloadedBytes, this.totalBytes, this.speedBytesSec, this.etaSecs}): super._();
  

 final  String taskId;
 final  double percent;
 final  BigInt downloadedBytes;
 final  BigInt? totalBytes;
 final  BigInt? speedBytesSec;
 final  BigInt? etaSecs;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Event_DownloadProgressCopyWith<Event_DownloadProgress> get copyWith => _$Event_DownloadProgressCopyWithImpl<Event_DownloadProgress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Event_DownloadProgress&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.percent, percent) || other.percent == percent)&&(identical(other.downloadedBytes, downloadedBytes) || other.downloadedBytes == downloadedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.speedBytesSec, speedBytesSec) || other.speedBytesSec == speedBytesSec)&&(identical(other.etaSecs, etaSecs) || other.etaSecs == etaSecs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,taskId,percent,downloadedBytes,totalBytes,speedBytesSec,etaSecs);
}

@override
String toString() {
    return 'Event.downloadProgress(taskId: $taskId, percent: $percent, downloadedBytes: $downloadedBytes, totalBytes: $totalBytes, speedBytesSec: $speedBytesSec, etaSecs: $etaSecs)';
}


}

/// @nodoc
abstract mixin class $Event_DownloadProgressCopyWith<$Res> implements $EventCopyWith<$Res> {
  factory $Event_DownloadProgressCopyWith(Event_DownloadProgress value, $Res Function(Event_DownloadProgress) _then) = _$Event_DownloadProgressCopyWithImpl;
@useResult
$Res call({
 String taskId, double percent, BigInt downloadedBytes, BigInt? totalBytes, BigInt? speedBytesSec, BigInt? etaSecs
});




}
/// @nodoc
class _$Event_DownloadProgressCopyWithImpl<$Res>
    implements $Event_DownloadProgressCopyWith<$Res> {
  _$Event_DownloadProgressCopyWithImpl(this._self, this._then);

  final Event_DownloadProgress _self;
  final $Res Function(Event_DownloadProgress) _then;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? taskId = null,Object? percent = null,Object? downloadedBytes = null,Object? totalBytes = freezed,Object? speedBytesSec = freezed,Object? etaSecs = freezed,}) {
  return _then(Event_DownloadProgress(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,percent: null == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as double,downloadedBytes: null == downloadedBytes ? _self.downloadedBytes : downloadedBytes // ignore: cast_nullable_to_non_nullable
as BigInt,totalBytes: freezed == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt?,speedBytesSec: freezed == speedBytesSec ? _self.speedBytesSec : speedBytesSec // ignore: cast_nullable_to_non_nullable
as BigInt?,etaSecs: freezed == etaSecs ? _self.etaSecs : etaSecs // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

/// @nodoc


class Event_DownloadFinished extends Event {
  const Event_DownloadFinished({required this.taskId, required this.track}): super._();
  

 final  String taskId;
 final  Track track;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Event_DownloadFinishedCopyWith<Event_DownloadFinished> get copyWith => _$Event_DownloadFinishedCopyWithImpl<Event_DownloadFinished>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Event_DownloadFinished&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.track, track) || other.track == track));
}


@override
int get hashCode {
    return Object.hash(runtimeType,taskId,track);
}

@override
String toString() {
    return 'Event.downloadFinished(taskId: $taskId, track: $track)';
}


}

/// @nodoc
abstract mixin class $Event_DownloadFinishedCopyWith<$Res> implements $EventCopyWith<$Res> {
  factory $Event_DownloadFinishedCopyWith(Event_DownloadFinished value, $Res Function(Event_DownloadFinished) _then) = _$Event_DownloadFinishedCopyWithImpl;
@useResult
$Res call({
 String taskId, Track track
});




}
/// @nodoc
class _$Event_DownloadFinishedCopyWithImpl<$Res>
    implements $Event_DownloadFinishedCopyWith<$Res> {
  _$Event_DownloadFinishedCopyWithImpl(this._self, this._then);

  final Event_DownloadFinished _self;
  final $Res Function(Event_DownloadFinished) _then;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? taskId = null,Object? track = null,}) {
  return _then(Event_DownloadFinished(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,track: null == track ? _self.track : track // ignore: cast_nullable_to_non_nullable
as Track,
  ));
}


}

/// @nodoc


class Event_DownloadFailed extends Event {
  const Event_DownloadFailed({required this.taskId, required this.reason}): super._();
  

 final  String taskId;
 final  String reason;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Event_DownloadFailedCopyWith<Event_DownloadFailed> get copyWith => _$Event_DownloadFailedCopyWithImpl<Event_DownloadFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Event_DownloadFailed&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,taskId,reason);
}

@override
String toString() {
    return 'Event.downloadFailed(taskId: $taskId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $Event_DownloadFailedCopyWith<$Res> implements $EventCopyWith<$Res> {
  factory $Event_DownloadFailedCopyWith(Event_DownloadFailed value, $Res Function(Event_DownloadFailed) _then) = _$Event_DownloadFailedCopyWithImpl;
@useResult
$Res call({
 String taskId, String reason
});




}
/// @nodoc
class _$Event_DownloadFailedCopyWithImpl<$Res>
    implements $Event_DownloadFailedCopyWith<$Res> {
  _$Event_DownloadFailedCopyWithImpl(this._self, this._then);

  final Event_DownloadFailed _self;
  final $Res Function(Event_DownloadFailed) _then;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? taskId = null,Object? reason = null,}) {
  return _then(Event_DownloadFailed(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class Event_DownloadCancelled extends Event {
  const Event_DownloadCancelled({required this.taskId}): super._();
  

 final  String taskId;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Event_DownloadCancelledCopyWith<Event_DownloadCancelled> get copyWith => _$Event_DownloadCancelledCopyWithImpl<Event_DownloadCancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Event_DownloadCancelled&&(identical(other.taskId, taskId) || other.taskId == taskId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,taskId);
}

@override
String toString() {
    return 'Event.downloadCancelled(taskId: $taskId)';
}


}

/// @nodoc
abstract mixin class $Event_DownloadCancelledCopyWith<$Res> implements $EventCopyWith<$Res> {
  factory $Event_DownloadCancelledCopyWith(Event_DownloadCancelled value, $Res Function(Event_DownloadCancelled) _then) = _$Event_DownloadCancelledCopyWithImpl;
@useResult
$Res call({
 String taskId
});




}
/// @nodoc
class _$Event_DownloadCancelledCopyWithImpl<$Res>
    implements $Event_DownloadCancelledCopyWith<$Res> {
  _$Event_DownloadCancelledCopyWithImpl(this._self, this._then);

  final Event_DownloadCancelled _self;
  final $Res Function(Event_DownloadCancelled) _then;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? taskId = null,}) {
  return _then(Event_DownloadCancelled(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class Event_DownloadSkippedDuplicate extends Event {
  const Event_DownloadSkippedDuplicate({required this.taskId, required this.track}): super._();
  

 final  String taskId;
 final  Track track;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Event_DownloadSkippedDuplicateCopyWith<Event_DownloadSkippedDuplicate> get copyWith => _$Event_DownloadSkippedDuplicateCopyWithImpl<Event_DownloadSkippedDuplicate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Event_DownloadSkippedDuplicate&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.track, track) || other.track == track));
}


@override
int get hashCode {
    return Object.hash(runtimeType,taskId,track);
}

@override
String toString() {
    return 'Event.downloadSkippedDuplicate(taskId: $taskId, track: $track)';
}


}

/// @nodoc
abstract mixin class $Event_DownloadSkippedDuplicateCopyWith<$Res> implements $EventCopyWith<$Res> {
  factory $Event_DownloadSkippedDuplicateCopyWith(Event_DownloadSkippedDuplicate value, $Res Function(Event_DownloadSkippedDuplicate) _then) = _$Event_DownloadSkippedDuplicateCopyWithImpl;
@useResult
$Res call({
 String taskId, Track track
});




}
/// @nodoc
class _$Event_DownloadSkippedDuplicateCopyWithImpl<$Res>
    implements $Event_DownloadSkippedDuplicateCopyWith<$Res> {
  _$Event_DownloadSkippedDuplicateCopyWithImpl(this._self, this._then);

  final Event_DownloadSkippedDuplicate _self;
  final $Res Function(Event_DownloadSkippedDuplicate) _then;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? taskId = null,Object? track = null,}) {
  return _then(Event_DownloadSkippedDuplicate(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,track: null == track ? _self.track : track // ignore: cast_nullable_to_non_nullable
as Track,
  ));
}


}

/// @nodoc


class Event_YtdlpStatus extends Event {
  const Event_YtdlpStatus({required this.present, this.version, required this.outdated, this.lastChecked, this.message}): super._();
  

 final  bool present;
 final  String? version;
 final  bool outdated;
 final  String? lastChecked;
 final  String? message;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Event_YtdlpStatusCopyWith<Event_YtdlpStatus> get copyWith => _$Event_YtdlpStatusCopyWithImpl<Event_YtdlpStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Event_YtdlpStatus&&(identical(other.present, present) || other.present == present)&&(identical(other.version, version) || other.version == version)&&(identical(other.outdated, outdated) || other.outdated == outdated)&&(identical(other.lastChecked, lastChecked) || other.lastChecked == lastChecked)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,present,version,outdated,lastChecked,message);
}

@override
String toString() {
    return 'Event.ytdlpStatus(present: $present, version: $version, outdated: $outdated, lastChecked: $lastChecked, message: $message)';
}


}

/// @nodoc
abstract mixin class $Event_YtdlpStatusCopyWith<$Res> implements $EventCopyWith<$Res> {
  factory $Event_YtdlpStatusCopyWith(Event_YtdlpStatus value, $Res Function(Event_YtdlpStatus) _then) = _$Event_YtdlpStatusCopyWithImpl;
@useResult
$Res call({
 bool present, String? version, bool outdated, String? lastChecked, String? message
});




}
/// @nodoc
class _$Event_YtdlpStatusCopyWithImpl<$Res>
    implements $Event_YtdlpStatusCopyWith<$Res> {
  _$Event_YtdlpStatusCopyWithImpl(this._self, this._then);

  final Event_YtdlpStatus _self;
  final $Res Function(Event_YtdlpStatus) _then;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? present = null,Object? version = freezed,Object? outdated = null,Object? lastChecked = freezed,Object? message = freezed,}) {
  return _then(Event_YtdlpStatus(
present: null == present ? _self.present : present // ignore: cast_nullable_to_non_nullable
as bool,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,outdated: null == outdated ? _self.outdated : outdated // ignore: cast_nullable_to_non_nullable
as bool,lastChecked: freezed == lastChecked ? _self.lastChecked : lastChecked // ignore: cast_nullable_to_non_nullable
as String?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class Event_Notify extends Event {
  const Event_Notify({required this.kind, required this.message}): super._();
  

 final  String kind;
 final  String message;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Event_NotifyCopyWith<Event_Notify> get copyWith => _$Event_NotifyCopyWithImpl<Event_Notify>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Event_Notify&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,message);
}

@override
String toString() {
    return 'Event.notify(kind: $kind, message: $message)';
}


}

/// @nodoc
abstract mixin class $Event_NotifyCopyWith<$Res> implements $EventCopyWith<$Res> {
  factory $Event_NotifyCopyWith(Event_Notify value, $Res Function(Event_Notify) _then) = _$Event_NotifyCopyWithImpl;
@useResult
$Res call({
 String kind, String message
});




}
/// @nodoc
class _$Event_NotifyCopyWithImpl<$Res>
    implements $Event_NotifyCopyWith<$Res> {
  _$Event_NotifyCopyWithImpl(this._self, this._then);

  final Event_Notify _self;
  final $Res Function(Event_Notify) _then;

/// Create a copy of Event
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? message = null,}) {
  return _then(Event_Notify(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class Event_LibraryChanged extends Event {
  const Event_LibraryChanged(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Event_LibraryChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Event.libraryChanged()';
}


}




// dart format on
