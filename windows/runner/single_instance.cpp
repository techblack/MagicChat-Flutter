#include "single_instance.h"

namespace {
constexpr wchar_t kActivationEventName[] =
    L"Local\\cloud.baizhi.chat.Activate";
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\cloud.baizhi.chat.SingleInstance";
}  // namespace

SingleInstance::SingleInstance() {
  activation_event_ =
      CreateEventW(nullptr, FALSE, FALSE, kActivationEventName);
  SetLastError(ERROR_SUCCESS);
  mutex_ = CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (mutex_ != nullptr) {
    is_primary_ = GetLastError() != ERROR_ALREADY_EXISTS;
  }
}

SingleInstance::~SingleInstance() {
  if (is_primary_ && mutex_ != nullptr) {
    ReleaseMutex(mutex_);
  }
  if (mutex_ != nullptr) {
    CloseHandle(mutex_);
  }
  if (activation_event_ != nullptr) {
    CloseHandle(activation_event_);
  }
}

bool SingleInstance::IsValid() const {
  return activation_event_ != nullptr && mutex_ != nullptr;
}

bool SingleInstance::IsPrimary() const {
  return is_primary_;
}

bool SingleInstance::NotifyPrimary() const {
  return SetEvent(activation_event_) != FALSE;
}

HANDLE SingleInstance::activation_event() const {
  return activation_event_;
}
