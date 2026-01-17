Rails.application.routes.draw do
  get 'default_settings/index'
  get 'default_settings/edit'
  get 'default_settings/update'
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  get "/login", to: "sessions#new"
  post "/local_login", to: "sessions#create_local"
  post "/rfid_login", to: "sessions#create_rfid"
  get "/rfid_login/wait", to: "sessions#rfid_wait", as: :rfid_wait
  get "/rfid_login/verify", to: "sessions#rfid_verify", as: :rfid_verify
  get "/rfid_login/check_webhook", to: "sessions#rfid_check_webhook", as: :rfid_check_webhook
  post "/rfid_login/submit_pin", to: "sessions#rfid_submit_pin", as: :rfid_submit_pin
  delete "/logout", to: "sessions#destroy"
  match "/auth/:provider/callback", to: "sessions#create", via: %i[get post]
  get "/auth/failure", to: "sessions#failure"

  post "/webhooks/rfid", to: "webhooks#rfid"
  post "/webhooks/kofi", to: "webhooks#kofi"
  post "/webhooks/access", to: "webhooks#access"

  resources :users, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
    member do
      post :activate
      post :deactivate
      post :ban
      post :mark_deceased
    end
    collection do
      post :sync
    end
  end

  resources :rfids, only: [:new, :create, :destroy]

  resources :slack_users, only: [:index, :show] do
    collection do
      post :sync
      post :sync_to_users
      post :import_members
      post :import_analytics
    end
    member do
      post :link_user
    end
  end

  resources :sheet_entries, only: [:index, :show] do
    collection do
      post :sync
      post :sync_to_users
      get :test
    end
    member do
      post :sync_to_user
    end
  end

  resources :paypal_payments, only: [:index, :show] do
    collection do
      post :sync
      get :test
      get :export
      post :import
    end
    member do
      post :link_user
    end
  end

  resources :recharge_payments, only: [:index, :show] do
    collection do
      post :sync
      get :test
      get :export
      post :import
    end
    member do
      post :link_user
    end
  end

  resources :kofi_payments, only: [:index, :show] do
    collection do
      get :export
      post :import
      post :import_csv
    end
    member do
      post :link_user
    end
  end

  resources :journals, only: [:index]

  resources :access_logs, only: [:index] do
    collection do
      get :generate_users_json
    end
  end

  get "/search", to: "search#index", as: :search

  get "/settings", to: "settings#index", as: :settings
  resources :training_topics, only: [:index, :create, :edit, :update, :destroy] do
    member do
      delete :revoke_training
      delete :revoke_trainer_capability
    end
  end
  resources :membership_plans, except: [:show]
  resources :rfid_readers, except: [:show] do
    member do
      post :regenerate_key
    end
  end
  resource :default_settings, only: [:show, :edit, :update], path: "settings/defaults"
  
  resources :email_templates, only: [:index, :show, :edit, :update] do
    member do
      get :preview
      post :toggle
      post :test_send
    end
    collection do
      post :seed
    end
  end

  resources :payment_processors, only: [:index, :show, :edit, :update] do
    member do
      post :toggle
      post :refresh_stats
    end
    collection do
      post :refresh_all
      post :seed
    end
  end

  resources :member_sources, only: [:index, :show, :edit, :update] do
    member do
      post :toggle
      post :refresh_stats
    end
    collection do
      post :refresh_all
      post :seed
    end
  end

  resources :access_controllers do
    member do
      post :toggle
    end
  end

  resources :access_controller_types, only: [:index, :new, :create, :edit, :update, :destroy] do
    member do
      post :toggle
    end
  end
  
  resources :incident_reports do
    member do
      post :add_link
      delete 'links/:link_id', action: :remove_link, as: :remove_link
    end
  end

  get "/reports", to: "reports#index", as: :reports
  get "/reports/:report_type/all", to: "reports#view_all", as: :reports_view_all
  post "/reports/update_user", to: "reports#update_user", as: :reports_update_user
  
  require 'sidekiq/web'
  mount Sidekiq::Web => '/goh7zeeNiezoozaingothu4'
  
  resources :applications do
    resources :application_groups, except: [:index] do
      member do
        post :add_user
        delete :remove_user
      end
    end
  end
end
