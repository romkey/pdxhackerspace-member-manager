Rails.application.routes.draw do
  get 'default_settings/index'
  get 'default_settings/edit'
  get 'default_settings/update'
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  get "/login", to: "sessions#new"
  get "/apply", to: "pages#apply"
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
  post "/webhooks/authentik", to: "webhooks#authentik"

  # Impersonation
  post "/impersonate/:user_id", to: "impersonations#create", as: :impersonate_user
  delete "/impersonate", to: "impersonations#destroy", as: :stop_impersonation

  resources :users, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
    member do
      post :activate
      post :deactivate
      post :ban
      post :mark_deceased
      post :sync_to_authentik
      post :sync_from_authentik
      post :mark_help_seen
    end
    collection do
      post :sync
    end
    resources :user_links, only: [:create, :update, :destroy]
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
      post :toggle_dont_link
    end
  end

  resources :authentik_users, only: [:index, :show] do
    collection do
      post :sync
    end
    member do
      post :link_user
      post :accept_changes
      post :push_to_authentik
    end
  end

  # Authentik webhook configuration
  get "/settings/authentik_webhooks", to: "authentik_webhooks#index", as: :authentik_webhooks
  post "/settings/authentik_webhooks/setup", to: "authentik_webhooks#setup", as: :setup_authentik_webhooks
  delete "/settings/authentik_webhooks/teardown", to: "authentik_webhooks#teardown", as: :teardown_authentik_webhooks

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
      get :unmatched_subjects
    end
    member do
      post :link_user
      post :toggle_dont_link
      post :create_member
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
      post :toggle_dont_link
      post :create_member
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

  # Training members
  get "/train", to: "trainings#index", as: :train_member
  post "/train/:user_id/add/:topic_id", to: "trainings#add_training", as: :add_training
  delete "/train/:user_id/remove/:topic_id", to: "trainings#remove_training", as: :remove_training
  post "/train/:user_id/trainer/:topic_id", to: "trainings#add_trainer_capability", as: :add_trainer_capability
  delete "/train/:user_id/trainer/:topic_id", to: "trainings#remove_trainer_capability", as: :remove_trainer_capability

  resources :access_logs, only: [:index] do
    collection do
      get :generate_users_json
      post :import
    end
  end

  get "/search", to: "search#index", as: :search

  get "/settings", to: "settings#index", as: :settings
  resources :training_topics, only: [:index, :create, :edit, :update, :destroy] do
    member do
      delete :revoke_training
      delete :revoke_trainer_capability
    end
    resources :links, controller: 'training_topic_links', only: [:create, :update, :destroy]
  end
  resources :membership_plans
  resources :rfid_readers, except: [:show] do
    member do
      post :regenerate_key
    end
  end
  resource :default_settings, only: [:show, :edit, :update], path: "settings/defaults"
  resource :membership_settings, only: [:show, :edit, :update], path: "settings/membership"
  
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

  resources :text_fragments, only: [:index, :show, :edit, :update] do
    collection do
      post :seed
    end
  end

  resources :documents do
    member do
      get :download
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
      post :sync
      post :run_verb
    end
    collection do
      post :sync_all
    end
  end

  resources :access_controller_types, only: [:index, :new, :create, :edit, :update, :destroy] do
    member do
      post :toggle
      post :probe
    end
    collection do
      get :export_users
    end
  end
  
  resources :incident_reports do
    member do
      post :add_link
      delete 'links/:link_id', action: :remove_link, as: :remove_link
      delete 'photos/:photo_id', action: :remove_photo, as: :remove_photo
      get :download_pdf
      get 'photos/:photo_id/download', action: :download_photo, as: :download_photo
    end
  end

  get "/reports", to: "reports#index", as: :reports
  get "/reports/:report_type/all", to: "reports#view_all", as: :reports_view_all
  post "/reports/update_user", to: "reports#update_user", as: :reports_update_user
  get "/api/users/search", to: "api/users#search", as: :api_users_search
  
  require 'sidekiq/web'
  mount Sidekiq::Web => '/goh7zeeNiezoozaingothu4'
  
  resources :applications do
    resources :application_groups, except: [:index] do
      member do
        post :add_user
        delete :remove_user
        post :sync_to_authentik
      end
    end
  end
end
