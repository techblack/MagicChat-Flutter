#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

class SingleInstance {
 public:
  SingleInstance();
  ~SingleInstance();

  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  bool IsValid() const;
  bool IsPrimary() const;
  bool NotifyPrimary() const;
  HANDLE activation_event() const;

 private:
  HANDLE activation_event_ = nullptr;
  HANDLE mutex_ = nullptr;
  bool is_primary_ = false;
};

#endif  // RUNNER_SINGLE_INSTANCE_H_
